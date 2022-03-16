library(dplyr)
library(jsonlite)
library(DBI)
library(httr)
library(curl)


connect_to_tweet_stream <- function() {
  bearer_token <- readRDS(file = "twitter_bearer_token.rds")
  
  if (substr(bearer_token, 1, 7) == "Bearer ") {
    bearer_token <- bearer_token
  } else{
    bearer_token <- paste0("Bearer ", bearer_token)
  }
  
  url <- "https://api.twitter.com/2/tweets/search/stream"
  
  h <- new_handle()
  handle_setheaders(h, "Authorization" = bearer_token)
  
  
  url <-
    "https://api.twitter.com/2/tweets/search/stream?tweet.fields=author_id,created_at&expansions=geo.place_id&place.fields=contained_within,country,country_code,full_name,geo,id,name,place_type"
  con <- curl(url = url, handle = h)
  
  
  tryCatch({
    stream_in(
      con,
      verbose = T,
      handler = function(tweet) {
        if (length(tweet)) {
          try({
            id  <- tweet$data$id;
            author_id <- tweet$data$author_id;
            tweet_text <- tweet$data$text;
            
            if (!is.null(tweet_text)) {
              location <-
                str_extract(tweet_text, "[0-9]*\\.[0-9]*,[0-9]*\\.[0-9]*");
            }
            # only save geotagged tweets (has includes places)
            if ("includes" %in% colnames(tweet))
            {
              url <- paste0('https://twitter.com/', author_id, '/status/', id);
              embed_code <- get_tweet_embed_code(url);
              tweet$data$embed_code <- embed_code;
              insert_tweet_in_db(tweet);
            } else if (!is.null(location) & !is.na(location)) {
              url <- paste0('https://twitter.com/', author_id, '/status/', id);
              embed_code <- get_tweet_embed_code(url);
              tweet$data$embed_code <- embed_code;
              tweet$data$location <- location;
              insert_tweet_in_db(tweet);
            }
          })
        }
      },
      pagesize = 1
    )
  }, error = function(cond) {
    print(cond)
    
    if (grepl('429', cond$message)) {
      print(cond)
      
      Sys.sleep(500)
      
    }
    Sys.sleep(10)
    
    connect_to_tweet_stream()
    
  })
}

insert_tweet_in_db <- function(tweet) {
  con <- dbConnect(RSQLite::SQLite(), "db.sqlite")
  
  tryCatch({
    if ("includes" %in% colnames(tweet)) {
      includes <- tweet$includes
      places <- includes$places
      places <- flatten(as.data.frame(places))
      places$lat <-
        sapply(places$geo.bbox, function(x) {
          (x[2] + x[4]) / 2
        })
      places$lng <-
        sapply(places$geo.bbox, function(x) {
          (x[1] + x[3]) / 2
        })
      places$geo.bbox <-
        sapply(places$geo.bbox, function(x) {
          toString(x)
        })
      places <- places %>%
        rename(bbox = geo.bbox,
               type = geo.type)
    } else {
      location <- tweet$data$location;
      coords <- str_split(location, ",")[[1]];
      lat <- coords[1];
      lng <- coords[2];
      id <- random_id(bytes = 8);
      tweet$data$place_id <- id;
      places <- data.frame(
        id = id,
        lat = lat,
        lng = lng,
        type = 'custom',
        place_type = '',
        full_name = '',
        country_code = 'unknown',
        name = '',
        country = 'unknown',
        bbox = ''
      )
    }
    
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
    message(cond);
    # Choose a return value in case of error
    return(NA)
  })
  tweet <- tweet$data
  if (! "place_id" %in% colnames(tweet))
  {    
    tweet <- mutate(tweet, place_id = geo$place_id);
  }
  
  tweet <-
    subset(tweet,
           select = c(
             'id',
             'text',
             'created_at',
             'place_id',
             'author_id',
             'embed_code'
           ))
  
  dbWriteTable(
    con,
    value = tweet,
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
  
  
  res <- dbSendQuery(con,
                     paste0("SELECT max(datetime(created_at)) from tweet"))
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
