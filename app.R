library(shiny)
library(shinyjs)
library(dplyr)
library(leaflet)
library(timevis)
library(htmlwidgets)
library(shinythemes)
library(bslib)


source("helpers.R")


ui <- bootstrapPage(
  tags$head(
    includeHTML("meta.html"),
    includeCSS("styles.css"),
    
    tags$script(src = "https://cdnjs.cloudflare.com/ajax/libs/iframe-resizer/3.5.16/iframeResizer.contentWindow.min.js",
                type = "text/javascript"),
    tags$script(src = "custom.js", type = "text/javascript")
  ),
  
  
  navbarPage(
    theme = shinytheme("cosmo"),
    collapsible = TRUE,
    HTML(
      '<a style="text-decoration:none;cursor:default;color:#FFFFFF;" class="active" href="#">timefli.es</a>'
    ),
    id = "nav",
    windowTitle = "timefli.es",
    
    tabPanel(
      "Tweet Map",
      div(
        class = "outer",
        leafletOutput("map", width = "100%", height = "100%"),
        timevisOutput("timeline"),
        absolutePanel(
          id = "description",
          class = "panel panel-default",
          top = 85,
          left = 15,
          width = 250,
          fixed = TRUE,
          draggable = TRUE,
          height = "auto",
          div(
            "Want your tweet on this map? Send a ",
            tags$a(href = 'https://help.twitter.com/en/using-twitter/tweet-location', "geo-tagged"),
            " tweet with the hashtag",
            tags$a(href = 'https://twitter.com/search?q=%23timeflies', "#timeflies"),
            " or just click on the button below and I'd be happy if you join a picture!",
            includeHTML("twitter-button.html")
          )
        )
      )
    ),
    tabPanel("About", includeHTML("about.html")),
    nav_item(a(href="http://github.com/jcolot/timefli.es", class="github-icon", target="_blank", includeHTML("github-icon.svg")))
  )
)

server <- function(input, output, session) {
  data <- reactivePoll(
    10000,
    session,
    checkFunc = function() {
      get_last_tweet_time()
    },
    valueFunc = function() {
      get_tweets_from_db()
    }
  )
  
  
  twitterIcon <- makeIcon(
    iconUrl = "twitter-icon.svg",
    iconWidth = 30,
    iconHeight = 30,
    iconAnchorX = 15,
    iconAnchorY = 15,
    popupAnchorY = -15,
    popupAnchorX = 1
  )
  
  tweets <- get_tweets_from_db()
  
  output$map <- renderLeaflet({
    leaflet(data(), options = leafletOptions(zoomControl = FALSE)) %>%
      addProviderTiles("OpenStreetMap.Mapnik") %>%
      addMarkers(
        lng = ~ lng,
        lat = ~ lat,
        popup = ~ embed_code,
        icon = twitterIcon,
        group = ~ id,
        clusterOptions = markerClusterOptions()
      ) %>%
      
      htmlwidgets::onRender(
        "function(el, x) {
			      map = this;
			      const event = new Event('mapReady');
            document.dispatchEvent(event);
			      L.control.zoom({
				      position:'topright'
			      }).addTo(this);
		      }"
      )
  })
  
  output$timeline <- renderTimevis(
    timevis(data(), options = list(
      type = 'point',
      height = 110,
      cluster = TRUE
    )) %>% htmlwidgets::onRender(
        "function(el, x) {
			     timevis = this;
			     const event = new Event('timelineReady');
           document.dispatchEvent(event);
		     }"
      )
   )
}
shinyApp(ui, server)
