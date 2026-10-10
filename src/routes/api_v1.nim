# SPDX-License-Identifier: AGPL-3.0-only
import asyncdispatch, strutils, strformat, times, json, options
import jester
import ".."/[types, api, redis_cache, utils, formatters, query]
import router_utils

proc userToJson*(user: User): JsonNode =
  result = %*{
    "id": user.id,
    "username": user.username,
    "fullname": user.fullname,
    "location": user.location,
    "website": user.website,
    "bio": user.bio,
    "avatar": user.userPic,
    "banner": user.banner,
    "following": user.following,
    "followers": user.followers,
    "tweetsCount": user.tweets,
    "likesCount": user.likes,
    "mediaCount": user.media,
    "verifiedType": $user.verifiedType,
    "protected": user.protected,
    "suspended": user.suspended
  }

proc tweetToJson*(tweet: Tweet): JsonNode =
  if tweet == nil or tweet.id == 0:
    return newJNull()

  var mediaArr = newJArray()
  for m in tweet.media:
    case m.kind
    of photoMedia:
      mediaArr.add(%*{"type": "photo", "url": m.photo.url, "alt": m.photo.altText})
    of videoMedia:
      mediaArr.add(%*{"type": "video", "thumb": m.video.thumb, "durationMs": m.video.durationMs, "url": m.video.url})
    of gifMedia:
      mediaArr.add(%*{"type": "gif", "thumb": m.gif.thumb, "url": m.gif.url})
  result = %*{
    "id": $tweet.id,
    "text": tweet.text,
    "time": $tweet.time,
    "user": {
      "username": tweet.user.username,
      "fullname": tweet.user.fullname,
      "avatar": tweet.user.userPic,
      "verifiedType": $tweet.user.verifiedType
    },
    "stats": {
      "replies": tweet.stats.replies,
      "retweets": tweet.stats.retweets,
      "likes": tweet.stats.likes,
      "views": tweet.stats.views
    },
    "media": mediaArr,
    "isQuote": tweet.quote.isSome,
    "isRetweet": tweet.retweet.isSome
  }

proc createRestApiRouter*(cfg: Config) =
  router restApi:
    # Set JSON Header & CORS
    before:
      if request.path.startsWith("/api/v1"):
        responseHeaders().get.add(("Content-Type", "application/json; charset=utf-8"))
        responseHeaders().get.add(("Access-Control-Allow-Origin", "*"))
        responseHeaders().get.add(("Access-Control-Allow-Methods", "GET, OPTIONS"))
        responseHeaders().get.add(("Access-Control-Allow-Headers", "Content-Type, Authorization"))

    get "/api/v1/user/@username":
      cond @"username".len > 0
      try:
        let user = await getCachedUser(@"username")
        if user.username.len == 0:
          resp Http404, $(%*{"error": "User not found", "code": 404})
        resp Http200, $(%*{"data": userToJson(user)})
      except CatchableError as e:
        resp Http500, $(%*{"error": e.msg, "code": 500})

    get "/api/v1/tweets/@username":
      cond @"username".len > 0
      try:
        let user = await getCachedUser(@"username")
        if user.username.len == 0:
          resp Http404, $(%*{"error": "User not found", "code": 404})
        let after = request.params.getOrDefault("cursor")
        let profile = await getGraphUserTweets(user.id, TimelineKind.tweets, after)
        var arr = newJArray()
        for tweetGroup in profile.tweets.content:
          for t in tweetGroup:
            arr.add(tweetToJson(t))
        resp Http200, $(%*{
          "data": arr,
          "cursor": {
            "top": profile.tweets.top,
            "bottom": profile.tweets.bottom
          }
        })
      except CatchableError as e:
        resp Http500, $(%*{"error": e.msg, "code": 500})

    get "/api/v1/tweet/@id":
      cond @"id".len > 0
      try:
        let conv = await getTweet(@"id", "", Relevance)
        if conv == nil or conv.tweet == nil or conv.tweet.id == 0:
          resp Http404, $(%*{"error": "Tweet not found", "code": 404})
        var repliesArr = newJArray()
        for chain in conv.replies.content:
          for r in chain.content:
            repliesArr.add(tweetToJson(r))
        resp Http200, $(%*{
          "data": tweetToJson(conv.tweet),
          "replies": repliesArr
        })
      except CatchableError as e:
        resp Http500, $(%*{"error": e.msg, "code": 500})

    get "/api/v1/search":
      try:
        let qText = request.params.getOrDefault("q")
        if qText.len == 0:
          resp Http400, $(%*{"error": "Missing 'q' query parameter", "code": 400})
        var q = Query(text: qText, kind: QueryKind.tweets)
        let cursor = request.params.getOrDefault("cursor")
        let timeline = await getGraphTweetSearch(q, cursor)
        var arr = newJArray()
        for tweetGroup in timeline.content:
          for t in tweetGroup:
            arr.add(tweetToJson(t))
        resp Http200, $(%*{
          "data": arr,
          "cursor": {
            "top": timeline.top,
            "bottom": timeline.bottom
          }
        })
      except CatchableError as e:
        resp Http500, $(%*{"error": e.msg, "code": 500})
