$(document).on('ready', function() {
    navigator.geolocation.getCurrentPosition(onSuccess, onError);

    function onError(err) {
        Shiny.onInputChange("geolocation", false);
    }

    function onSuccess(position) {
        setTimeout(function() {
            var coords = position.coords;
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
        map.panTo(map.unproject(px), {
            animate: true
        });
    });
});


$(document).on('timelineReady', function() {
    $('.btn.zoom-out').text('−');
    timevis.timeline.on('mouseDown', function(el) {
        const item = timevis.timeline.itemSet.getItemById(el.item);
        if (!item) return;
        if (!item.isCluster) {
            const lat = item.data.lat;
            const lng = item.data.lng;
            map.panTo([lat, lng]);
            map.eachLayer(function(layer) {
                if (layer.options.group) {
                    if (layer.options.group == el.item) {
                        L.popup({
                                offset: [3, -7]
                            })
                            .setLatLng(layer.getLatLng())
                            .setContent(layer.options.popup)
                            .openOn(map);
                    }
                } else if (layer.getAllChildMarkers) {
                    layer.getAllChildMarkers().forEach(
                        function(marker) {
                            if (marker.options.group == el.item) {
                                L.popup({
                                        offset: [3, -7]
                                    })
                                    .setLatLng(layer.getLatLng())
                                    .setContent(marker.options.popup)
                                    .openOn(map);
                            }
                        }
                    )
                }
            });
        } else {
            const offset = (item.data.max - item.data.min) * 0.2;
            timevis.timeline.setWindow(item.data.min - offset, item.data.max + offset);
        }
    });
    timevis.timeline.itemSet.clusterGenerator._dropLevelsCache();
    timevis.timeline.itemSet.clusterGenerator.getClusters = function(oldClusters, scale, options) {
        let level = -1;
        let granularity = 2;
        let timeWindow = 0;

        if (scale > 0) {
            if (scale >= 1) {
                return [];
            }

            level = Math.abs(Math.round(Math.log(100 / scale) / Math.log(granularity)));
            timeWindow = Math.abs(Math.pow(granularity, level)) / 1.75;
        }

        // clear the cache when and re-generate groups the data when needed.
        if (this.dataChanged) {
            const levelChanged = (level != this.cacheLevel);
            const applyDataNow = this.applyOnChangedLevel ? levelChanged : true;
            if (applyDataNow) {
                this._dropLevelsCache();
                this._filterData();
            }
        }

        this.cacheLevel = level;
        if (this.cache[level])
            return this.cache[level];

        let clusters = [];
        for (let groupName in this.groups) {
            if (this.groups.hasOwnProperty(groupName)) {

                const items = this.groups[groupName];
                if (items.length == 0) continue;
                const clusterItemsArray = [];
                // initialize first clusterItemsArray
                clusterItemsArray.push([]);
                let previousItem = items[0];
                items.forEach(function(item) {
                    if (item.center - previousItem.center <= timeWindow) {
                        clusterItemsArray[clusterItemsArray.length - 1].push(item)
                    } else {
                        clusterItemsArray.push([item])
                    };
                    previousItem = item;
                });

                let i = 0;

                while (i < clusterItemsArray.length) {
                    if (clusterItemsArray[i].length == 1) {
                        clusterItemsArray.splice(i, 1);
                    } else {
                        i++
                    }
                }

                if (clusterItemsArray.length == 0) continue;

                // try splitting clusterItems while they contain too much items
                while (true) {
                    let clusterItemsArrayLength = clusterItemsArray.length;
                    let i = 0;
                    do {
                        // check if cluster items are too close from each other, if yes, split in two
                        const clusterItems = clusterItemsArray[i];
                        const minCenter = clusterItems[0].center;
                        const maxCenter = clusterItems[clusterItems.length - 1].center;
                        if (maxCenter - minCenter > 2 * timeWindow) {
                            let j = 0;
                            let newClusterItems = [];
                            while (j < clusterItems.length) {
                                if (maxCenter - clusterItems[j].center < clusterItems[j].center - minCenter) {
                                    newClusterItems.push(clusterItems.splice(j, 1)[0]);
                                } else {
                                    j++;
                                }
                            }
                            if (newClusterItems.length) {
                                let clusterItemsCenter = clusterItems.map(a => a.center).reduce((a, b) => a + b, 0) / clusterItems.length;
                                let newClusterItemsCenter = newClusterItems.map(a => a.center).reduce((a, b) => a + b, 0) / newClusterItems.length;
                                if (newClusterItemsCenter - clusterItemsCenter > timeWindow) {
                                    // insert a new cluster
                                    clusterItemsArray.splice(i + 1, 0, newClusterItems);
                                    // else abort if new  cluster is too close
                                } else {
                                    clusterItems.push(...newClusterItems);
                                }
                            }
                        }
                        i++;
                    } while (i < clusterItemsArray.length);
                    if (clusterItemsArray.length == clusterItemsArrayLength) break;
                }

                const groupId = this.itemSet.getGroupId(items[0].data);
                const group = this.itemSet.groups[groupId] || this.itemSet.groups[ReservedGroupIds.UNGROUPED];

                clusterItemsArray.forEach((clusterItems, i) => {
                    let cluster = this._getClusterForItems(clusterItems, group, oldClusters, options);
                    clusters.push(cluster);
                });

            }
        }

        this.cache[level] = clusters;
        return clusters;
    }
});
