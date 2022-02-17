$(document).on('ready', function() {
    navigator.geolocation.getCurrentPosition(onSuccess, onError);

    function onError(err) {
        Shiny.onInputChange("geolocation", false);
    }

    function onSuccess(position) {
        setTimeout(function() {
            var coords = position.coords;
            console.log(coords.latitude + ", " + coords.longitude);
            Shiny.onInputChange("geolocation", true);
            Shiny.onInputChange("lat", coords.latitude);
            Shiny.onInputChange("long", coords.longitude);
        }, 1100)
    }

});

$(document).on('mapReady', function() {

    map.on('popupopen', function(e) {
        $.getScript("https://platform.twitter.com/widgets.js");
        var px = map.project(e.popup._latlng);
        px.y -= e.popup._container.clientHeight;
        map.panTo(map.unproject(px),{animate: true});
    });
});


$(document).on('timelineReady', function() {
    $('.btn.zoom-out').text('−');
    timevis.timeline.on('mouseDown', function(el) {
        console.log(el);
        var item = timevis.timeline.itemSet.items[el.item];
        var lat = item.data.lat;
        var lng = item.data.lng;
        map.panTo([lat, lng]);
        map.eachLayer(function(layer) {
            if (layer.options.group) {
                if (layer.options.group == el.item) {
                    L.popup({offset: [3, -7]})
                        .setLatLng(layer.getLatLng())
                        .setContent(layer.options.popup)
                        .openOn(map);
                }
            } else if (layer.getAllChildMarkers) {
                layer.getAllChildMarkers().forEach(
                    function(marker) {
                        if (marker.options.group == el.item) {
                            L.popup({offset: [3, -7]})
                                .setLatLng(layer.getLatLng())
                                .setContent(marker.options.popup)
                                .openOn(map);
                        }
                    }
                )
            }
        });
    });
});
