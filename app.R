library(shiny)
library(shinyjs)
library(dplyr)
library(leaflet)
library(timevis)
library(htmlwidgets)
source("helpers.R")


#Sys.setenv(OPENCAGE_KEY = readRDS("opencage_api.rds"))

ui <- bootstrapPage(
    tags$head(
        tags$link(href = "https://fonts.googleapis.com/css?family=Oswald", rel = "stylesheet"),
    includeHTML("meta.html"),
    tags$script(src="https://cdnjs.cloudflare.com/ajax/libs/iframe-resizer/3.5.16/iframeResizer.contentWindow.min.js",
    type="text/javascript"),
    tags$script(src="custom.js", type="text/javascript")
  ),
  
  leafletOutput("map", width = "100%", height = "100%"),
  timevisOutput("timeline"),
  absolutePanel(
    id='brand',
    tags$h2("timefli.es")
  )
)

server <- function(input, output, session) {
  
  data <- reactivePoll(10000, session,
                       checkFunc = function() {
                         get_last_tweet_time()
                       },
                       valueFunc = function() {
                         get_tweets_from_db()
                       }
  )
  
  
  twitterIcon <- makeIcon(
    iconUrl = "twitter-icon.svg",
    iconWidth = 30, iconHeight = 30,
    iconAnchorX = 15, iconAnchorY = 15,
    popupAnchorY = -15, popupAnchorX = 1
  )
  
  tweets <- get_tweets_from_db()
  
  output$map <- renderLeaflet({
    leaflet(data(), options = leafletOptions(zoomControl = FALSE)) %>%
      addProviderTiles("OpenStreetMap.Mapnik") %>%
      addMarkers(lng = ~lng, lat = ~lat, popup = ~embed_code, icon = twitterIcon, group = ~id, clusterOptions = markerClusterOptions()) %>%
      
      htmlwidgets::onRender(
        "function(el, x) {
			      map = this;
			      const event = new Event('mapReady');
            document.dispatchEvent(event);
			      L.control.zoom({
				      position:'topright'
			      }).addTo(this);
		      }"
      ) %>%
      setView(4.406470, 50.830130, zoom = 6)
  })

  output$timeline <- renderTimevis(
    timevis(data(), options = list(type = 'point', height= 110, cluster = TRUE)) %>%
      htmlwidgets::onRender(
        "function(el, x) {
			      timevis = this;
			      const event = new Event('timelineReady');
            document.dispatchEvent(event);
		      }"
      )
  )
}
shinyApp(ui, server)
