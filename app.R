library(shiny)
library(shinyjs)
library(dplyr)
library(leaflet)
library(timevis)
library(htmlwidgets)


Sys.setenv(OPENCAGE_KEY = readRDS("opencage_api.rds"))

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
  
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(zoomControl = FALSE)) %>%
      addProviderTiles("OpenStreetMap.DE") %>%

      htmlwidgets::onRender(
		"function(el, x) {
			map = this;	
			L.control.zoom({
				position:'topright'
			}).addTo(this);


            var redIcon = new L.Icon({
                iconUrl: 'marker-icon-2x-red.png',
                shadowUrl: 'marker-shadow.png',
                iconSize: [25, 41],
                iconAnchor: [12, 41],
                popupAnchor: [1, -34],
                shadowSize: [41, 41]
            });

            var marker = new L.marker([50.830130,4.406470], {icon: redIcon}).addTo(map);

		}") %>%
      setView(4.406470, 50.830130, zoom = 6)
  })

  output$timeline <- renderTimevis(
      timevis()
  )
}
shinyApp(ui, server)
