library(dplyr)
library(jsonlite)
library(DBI)

get_tweets_from_api <- function() {
  bearer_token <- readRDS(file = "twitter_bearer_token.rds")
  
  if (substr(bearer_token, 1, 7) == "Bearer ") {
    bearer_token <- bearer_token
  } else{
    bearer_token <- paste0("Bearer ", bearer_token)
  }
  
  url <- "https://api.twitter.com/2/users/1492628588046303237/tweets"
  
  #url <- "https://api.twitter.com/2/users/28131948/tweets"
  
  params = list(
    "max_results" = 5,
    "tweet.fields" = "author_id,created_at",
    "expansions" = "geo.place_id",
    "place.fields" = "contained_within,country,country_code,full_name,geo,id,name,place_type"
  )
  
  r <-
    httr::GET(url, httr::add_headers(Authorization = bearer_token), query =
                params)
  

  #fix random 503 errors
  count <- 0
  while (httr::status_code(r) == 503 & count < 4) {
    r <-
      httr::GET(url,
                httr::add_headers(Authorization = bearer_token),
                query = params)
    count <- count + 1
    Sys.sleep(count * 5)
  }
  
  if (httr::status_code(r) != 200) {
    stop(paste("something went wrong. Status code:", httr::status_code(r)))
    
  }
  if (httr::headers(r)$`x-rate-limit-remaining` == "1") {
    warning(paste(
      "x-rate-limit-remaining=1. Resets at",
      as.POSIXct(
        as.numeric(httr::headers(r)$`x-rate-limit-reset`),
        origin = "1970-01-01"
      )
    ))
  }
  tweets <- jsonlite::fromJSON(httr::content(r, "text"))
  con <- dbConnect(RSQLite::SQLite(), "db.sqlite")
  
  res <- dbSendQuery(
    con,
    paste0(
      "SELECT id from tweet where id in (", toString(tweets$data$id), ")"
    )
  )
  res <- dbFetch(res)

  new_tweets <<- merge(x = res, y = tweets$data, by = "id", all = TRUE)
  
  for( i in rownames(new_tweets)) {
    id  <- new_tweets[i, "id"]
    author_id <- new_tweets[i, "author_id"]
    url <- paste0('https://twitter.com/', author_id, '/status/', id)
    embed_code <- get_tweet_embed_code(url)
    tweets$data$embed_code[which(tweets$data$id == id)] <- embed_code
  }
  
  tweets
}

insert_tweets_in_db <- function() {
  con <- dbConnect(RSQLite::SQLite(), "db.sqlite")
  tweets <- get_tweets_from_api()
  
  tryCatch({
    includes <- tweets$includes
    places <- includes$places
    places <- flatten(places)
    places$lat <- sapply(places$geo.bbox, function(x){(x[2] + x[4]) / 2})
    places$lng <- sapply(places$geo.bbox, function(x){(x[1] + x[3]) / 2})
    places$geo.bbox <-sapply(places$geo.bbox, function(x) {toString(x)}) 
    places <- as.data.frame(places)
    places <- places %>% 
      rename(
        bbox = geo.bbox,
        type = geo.type
      )

    dbWriteTable(
      con,
      value = places,
      name = "place_temp",
      overwrite = TRUE,
      row.names = FALSE
    )
    
    dbSendQuery(
      con,
      paste0(
        "INSERT INTO place (place_type, full_name, country_code, id, name, country, type, bbox, lat, lng)",
        " SELECT place_temp.place_type, ",
        "place_temp.full_name, ",
        "place_temp.country_code, ",
        "place_temp.id, ",
        "place_temp.name, ",
        "place_temp.country, ",
        "place_temp.type, ",
        "place_temp.bbox, ",
        "place_temp.lat, ",
        "place_temp.lng ",
        "FROM place_temp",
        " LEFT JOIN place",
        "   ON place_temp.id = place.id",
        " WHERE place.id IS NULL"
      )
    )
    
  }, error = function(cond) {
    message(cond)
    # Choose a return value in case of error
    return(NA)
  })
  tweets <- tweets$data
  tweets <- mutate(tweets, place_id = geo$place_id)
  tweets <- subset(tweets, select = c('id', 'text', 'created_at', 'place_id', 'author_id', 'embed_code'))

  dbWriteTable(
    con,
    value = tweets,
    name = "tweet_temp",
    overwrite = TRUE,
    row.names = FALSE
  )
  
  dbSendQuery(
    con,
    paste0(
      "INSERT INTO tweet (id, text, created_at, place_id, author_id, embed_code)",
      " SELECT tweet_temp.id, tweet_temp.text, tweet_temp.created_at, tweet_temp.place_id, tweet_temp.author_id, tweet_temp.embed_code",
      " FROM tweet_temp",
      " LEFT JOIN tweet",
      "   ON tweet_temp.id = tweet.id",
      " WHERE tweet.id IS NULL"
    )
  )
}


get_tweets_from_db <- function() {
  con <- dbConnect(RSQLite::SQLite(), "db.sqlite")
  
  
  res <- dbSendQuery(
    con,
    paste0(
      "SELECT tweet.id as id,",
      "tweet.text as text, ",
      "tweet.created_at as start, ",
      "tweet.embed_code as embed_code, ",
      "place.full_name as place_full_name, ",
      "place.country_code as place_country_code, ",
      "place.name as place_name, ",
      "place.country as place_country, ",
      "place.type as place_type, ",
      "place.bbox as place_bbox, ",
      "place.lat as lat,",
      "place.lng as lng ",
      " FROM tweet",
      " INNER JOIN place",
      "   ON tweet.place_id = place.id"
    )
  )
  res <- dbFetch(res)
  res <- as.data.frame(res)
  res
}

get_last_tweet_time <- function() {
  con <- dbConnect(RSQLite::SQLite(), "db.sqlite")
  
  
  res <- dbSendQuery(
    con,
    paste0(
      "SELECT max(datetime(created_at)) from tweet"
    )
  )
  res <- dbFetch(res)
  as.character(res)
}


get_tweet_embed_code <- function(tweet_url) {
    url <- httr::parse_url("https://publish.twitter.com/oembed")
    url$query <- list(
      url = tweet_url,
      maxwidth = 350,
      hide_thread = T,
      omit_script = F,
      align = "center",
      dnt = T
    )
    
    url <- httr::build_url(url)
    res <- httr::GET(url)
    httr::stop_for_status(res)
    if (!grepl("application/json", res$headers$`content-type`)) {
      stop("Expected json response, got ", res$headers$`content-type`)
    }
    res_txt <- httr::content(res, "text")
    res_json <- jsonlite::fromJSON(res_txt)
    htmltools::HTML(res_json$html)
}
