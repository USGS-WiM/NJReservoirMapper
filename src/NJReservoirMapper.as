// 01.07.13 - NE - Updates to gage height handling for reservoirs and streamgages.
// 09.05.12 - NE - Added update time for real-time results.
// 08.20.12 - NE - Changed click to identify to click on graphics with attributes.
// 08.06.12 - BAD - fixed issues with info window (WiMInfoWindow) for click event on each site type 
// 04.01.11 - JB - Added AS side logic for right-click and mousewheel
// 03.28.11 - JB - Template clean-up and updates 
// 06.28.10 - JB - Added new Wim LayerLegend component
// 03.26.10 - JB - Created
 /***
 * ActionScript file for NJ Reservoir Mapper */

import com.esri.ags.FeatureSet;
import com.esri.ags.Graphic;
import com.esri.ags.events.ExtentEvent;
import com.esri.ags.events.MapMouseEvent;
import com.esri.ags.geometry.Extent;
import com.esri.ags.geometry.MapPoint;
import com.esri.ags.layers.TiledMapServiceLayer;
import com.esri.ags.symbols.InfoSymbol;
import com.esri.ags.tasks.IdentifyTask;
import com.esri.ags.tasks.QueryTask;
import com.esri.ags.tasks.supportClasses.IdentifyParameters;
import com.esri.ags.tasks.supportClasses.IdentifyResult;
import com.esri.ags.tasks.supportClasses.Query;
import com.esri.ags.utils.WebMercatorUtil;
import com.esri.ags.virtualearth.VEGeocodeResult;

import flash.display.StageDisplayState;
import flash.events.Event;
import flash.events.MouseEvent;

import gov.usgs.wim.controls.WiMInfoWindow;
import gov.usgs.wim.controls.skins.WiMInfoWindowSkin;
import gov.usgs.wim.utils.XmlResourceLoader;

import mx.binding.utils.BindingUtils;
import mx.collections.ArrayCollection;
import mx.collections.Sort;
import mx.collections.SortField;
import mx.controls.*;
import mx.core.FlexGlobals;
import mx.core.IVisualElement;
import mx.core.IVisualElementContainer;
import mx.core.UIComponent;
import mx.events.CloseEvent;
import mx.events.FlexEvent;
import mx.events.ResizeEvent;
import mx.managers.CursorManager;
import mx.managers.PopUpManager;
import mx.resources.ResourceBundle;
import mx.rpc.AsyncResponder;
import mx.rpc.events.ResultEvent;
import mx.rpc.http.HTTPService;
import mx.utils.Base64Decoder;
import mx.utils.ObjectProxy;

import spark.collections.Sort;
import spark.collections.SortField;
import spark.components.Group;
import spark.components.HGroup;
import spark.components.SkinnableContainer;
import spark.components.supportClasses.SkinnableComponent;


			private var _queryWindow:WiMInfoWindow;

			public var _summaryWindow:WiMInfoWindow;

			private var xmlResourceLoader:XmlResourceLoader = new XmlResourceLoader();

			private var loadedSites:Boolean = false;	

			public var summaryTableIndex:int;

			public var reservoirCreationCompGlobal:Boolean = false;
			public var streamgageCreationCompGlobal:Boolean = false;
			public var combinedCreationCompGlobal:Boolean = false;


			//Initialize mapper
			private function setup():void
			{	
				xmlResourceLoader.load(["locale/en_US", "en_US"]);
				
				ExternalInterface.addCallback("rightClick", onRightClick);
				ExternalInterface.addCallback("handleWheel", handleWheel);
			}



			private function onRightClick():void {
				//Recenter at mouse location
				var cursorLocation:Point = new Point(contentMouseX, contentMouseY);
				map.centerAt(map.toMap(cursorLocation));
				//Zoom out
				map.zoomOut();
			}
			
			public function handleWheel(event:Object): void {
				var obj:InteractiveObject = null;
				var objects:Array = getObjectsUnderPoint(new Point(event.x, event.y));
				for (var i:int = objects.length - 1; i >= 0; i--) {
					if (objects[i] is InteractiveObject) {
						obj = objects[i] as InteractiveObject;
						break;
					} else {
						if (objects[i] is Shape && (objects[i] as Shape).parent) {
							obj = (objects[i] as Shape).parent;
							break;
						}
					}
				}
				if (obj) {
					var mEvent:MouseEvent = new MouseEvent(MouseEvent.MOUSE_WHEEL, true, false,
						event.x, event.y, obj,
						event.ctrlKey, event.altKey, event.shiftKey,
						false, -Number(event.delta));
					obj.dispatchEvent(mEvent);
				}
			}    	
			
			//Retrieves all reservoirs and stream gages for rendering in map
			private function getSites(event:FlexEvent):void
			{
				
				if (resourceManager.getString('urls', 'streamgagesReservoirs') != null && reservoirGraphicsLayer.graphicProvider.length == 0) {
					var identifyParameters:IdentifyParameters = new IdentifyParameters();
					identifyParameters.returnGeometry = true;
					identifyParameters.layerOption = "all";
					identifyParameters.width = map.width;
					identifyParameters.height = map.height;
					identifyParameters.geometry = map.extent;
					identifyParameters.mapExtent = map.extent;
					identifyParameters.spatialReference = map.spatialReference;
					
					var identifyTask:IdentifyTask = new IdentifyTask(resourceManager.getString( 'urls', 'streamgagesReservoirs'));
					identifyTask.execute(identifyParameters, new AsyncResponder(sitesResult, infoFault) );
				}
				
			}
			
			//sorts results of getSites and places them in the appropriate graphic layer
			private function sitesResult(resultSet:Array, configObjects:ArrayCollection) {
				if (resultSet.length != 0) {
					var i:int = 0;		
					for each (var result:IdentifyResult in resultSet) {
						i++;
						var resultLayerName:String = result.layerName;
						
						if (resultLayerName == 'Selected reservoirs') {
							
							result.feature.toolTip = result.feature.attributes.ResName + ' (' + result.feature.attributes.ResID + ')';
							reservoirGraphicsLayer.add(result.feature);
							
						} else if  (resultLayerName == 'Selected gages downstream of reservoirs') {
							
							trace(i + ": " + result.feature.attributes.StreamGageNm);
							result.feature.toolTip = result.feature.attributes.StreamGageNm + ' (' + result.feature.attributes.GageID + ')';
							streamGageGraphicsLayer.add(result.feature);
							
						}
						
						result.feature.addEventListener(MouseEvent.CLICK, function(event:MouseEvent):void {
							
							PopUpManager.removePopUp(_queryWindow);
							queryGraphicsLayer.clear();
							var aGraphic:Graphic = new Graphic();
							aGraphic.geometry = event.currentTarget.geometry;
							var siteLayerName:String = event.currentTarget.graphicsLayer.id;
							
							if (siteLayerName == 'reservoirGraphicsLayer') {
								
								_queryWindow = PopUpManager.createPopUp(map, ReservoirDataWindow, false) as WiMInfoWindow;
								aGraphic.symbol = circQuerySym;
								queryGraphicsLayer.add(aGraphic);
								
							} else if  (siteLayerName == 'streamGageGraphicsLayer') {
								_queryWindow = PopUpManager.createPopUp(map, StreamGagesDataWindow, false) as WiMInfoWindow;
								aGraphic.symbol = triQuerySym;
								queryGraphicsLayer.add(aGraphic);
							}
							_queryWindow.setStyle("skinClass", WiMInfoWindowSkin);
							_queryWindow.x = event.stageX;
							_queryWindow.y = event.stageY;
							_queryWindow.data = event.currentTarget.attributes;
							_queryWindow.addEventListener(CloseEvent.CLOSE, closePopUp);
						});
							
					}
					
					
					//Method for getting realtime info for all stream gages
					var dataRequest:HTTPService = new HTTPService();
					dataRequest.method = "GET";
					dataRequest.url = "http://fim.wim.usgs.gov/proxies/httpProxy/Default.aspx?site_no=";
					for (var i = 0; i < streamGageGraphicsLayer.graphicProvider.length; i++) {
						if (i < streamGageGraphicsLayer.graphicProvider.length-1) {
							dataRequest.url += streamGageGraphicsLayer.graphicProvider[i].attributes.GageID + ','; 
						} else {
							dataRequest.url += streamGageGraphicsLayer.graphicProvider[i].attributes.GageID; 
						}
					}
					dataRequest.url += "&dataTest=true"; //"http://waterdata.usgs.gov/nwis/inventory?agency_code=USGS&site_no=04103500";
					dataRequest.addEventListener(ResultEvent.RESULT, reqResult);
					dataRequest.send();
					
					function reqResult(event:ResultEvent):void
					{
						if (event.result != "") {
							var resultObj:Object = JSON.parse(event.result as String);
							for (var i = 0; i < resultObj.value.timeSeries.length; i++) {
								
								var gageID:String = resultObj.value.timeSeries[i].sourceInfo.siteCode[0].value;
								var paramCode:String = resultObj.value.timeSeries[i].variable.variableCode[0].value;
								var paramValue:String = resultObj.value.timeSeries[i].values[0].value[0].value;
								var dateTime:String = resultObj.value.timeSeries[i].values[0].value[0].dateTime;
								
								addAttributeToGraphic(gageID, paramCode, paramValue, dateTime);
								
							}
							var arrColl:ArrayCollection = new ArrayCollection();
							for each (var graphic:Graphic in streamGageGraphicsLayer.graphicProvider) {
								graphic.attributes.FloodCondition = parseFloat(graphic.attributes.FloodStage) - parseFloat(graphic.attributes.gageGageHeight);
								
								if (graphic.attributes.FloodStage == 'N/A') {
									graphic.attributes.gageCondition = "normal";
								} else if ((parseFloat(graphic.attributes.FloodStage) - parseFloat(graphic.attributes.gageGageHeight)) <= 0) {
									graphic.attributes.gageCondition = "flooding";
								} else if ((parseFloat(graphic.attributes.FloodStage) - parseFloat(graphic.attributes.gageGageHeight)) <= 1) {
									graphic.attributes.gageCondition = "nearFlood";
								} else if ((parseFloat(graphic.attributes.FloodStage) - parseFloat(graphic.attributes.gageGageHeight)) > 1) {
									graphic.attributes.gageCondition = "normal";
								}
								
								if (!graphic.attributes.hasOwnProperty('gageDischarge')) {
									graphic.attributes.gageDischarge = 'n.a.';
								}
								
								if (!graphic.attributes.hasOwnProperty('gageGageHeight')) {
									graphic.attributes.gageGageHeight = 'n.a.';
									graphic.attributes.gageGhDateTime = 'n.a.';
								}
								
								if (!graphic.attributes.hasOwnProperty('gageCondition')) {
									graphic.attributes.gageCondition = 'n.a.';
								}
							}
							
							streamGagesToggle.selected = true;
						}
					}
					
					//Method for getting realtime info for all reservoirs
					var resDataRequest:HTTPService = new HTTPService();
					resDataRequest.method = "GET";
					resDataRequest.url = "http://fim.wim.usgs.gov/proxies/httpProxy/Default.aspx?site_no=";
					for (var j = 0; j < reservoirGraphicsLayer.graphicProvider.length; j++) {
						if (j < reservoirGraphicsLayer.graphicProvider.length-1) {
							resDataRequest.url += reservoirGraphicsLayer.graphicProvider[j].attributes.ResID + ',';
						} else {
							resDataRequest.url += reservoirGraphicsLayer.graphicProvider[j].attributes.ResID;
						}
					}
					resDataRequest.url += "&dataTest=true"; //"http://waterdata.usgs.gov/nwis/inventory?agency_code=USGS&site_no=04103500";
					resDataRequest.addEventListener(ResultEvent.RESULT, resReqResult);
					resDataRequest.send();
					
					function resReqResult(event:ResultEvent):void
					{
						if (event.result != "") {
							var resultObj:Object = JSON.parse( event.result as String );
							for (var i = 0; i < resultObj.value.timeSeries.length; i++) {
								
								//Look for possible parameter codes and find sites without these values
								//maybe loop this resultObj to build list of sites and codes
								
								var resID:String = resultObj.value.timeSeries[i].sourceInfo.siteCode[0].value;
								var paramCode:String = resultObj.value.timeSeries[i].variable.variableCode[0].value;
								var paramValue:String = resultObj.value.timeSeries[i].values[0].value[0].value;
								var dateTime:String = resultObj.value.timeSeries[i].values[0].value[0].dateTime;
								
								addAttributeToGraphic(resID, paramCode, paramValue, dateTime);
								
							}
							var arrColl:ArrayCollection = new ArrayCollection();
							for each (var graphic:Graphic in reservoirGraphicsLayer.graphicProvider) {
								var gageHeight:Number = parseFloat(graphic.attributes.resGageHeight);
								var cap90:Number = parseFloat(graphic.attributes.cap_90);
								var spillStage:Number = parseFloat(graphic.attributes.spill_stage);
								if (gageHeight >= spillStage) {
									graphic.attributes.ResCondition = "spill";
								} else if (gageHeight <= spillStage && gageHeight >= cap90) {
									graphic.attributes.ResCondition = "above90";
								} else if (gageHeight < cap90) {
									graphic.attributes.ResCondition = "below90";
								} else {
									graphic.attributes.ResCondition = "below90";
								}
								
								
								if (!graphic.attributes.hasOwnProperty('gageGageHeight')) {
									graphic.attributes.gageGageHeight = 'n.a.';
									graphic.attributes.gageGhDateTime = 'n.a.';
								}
								
								if (!graphic.attributes.hasOwnProperty('resGageHeight')) {
									graphic.attributes.resGageHeight = 'n.a.';
									graphic.attributes.resGhDateTime = 'n.a.';
								}
								
								if (!graphic.attributes.hasOwnProperty('resLatestVolume')) {
									graphic.attributes.resLatestVolume = 'n.a.';
									graphic.attributes.resLVDateTime = 'n.a.';
								}
								
								if (!graphic.attributes.hasOwnProperty('resElevation')) {
									graphic.attributes.resElevation = 'n.a.';
									graphic.attributes.resElevDateTime = 'n.a.';
								}
								if (!graphic.attributes.hasOwnProperty('resLatestCapacity')) {
									graphic.attributes.resLatestCapacity = 'n.a.';
									graphic.attributes.resLCDateTime = 'n.a.';
								}
								if (!graphic.attributes.hasOwnProperty('resUsableCapacity')) {
									graphic.attributes.resUsableCapacity = 'n.a.';
									graphic.attributes.resUCDateTime = 'n.a.';
								}
								if (!graphic.attributes.hasOwnProperty('gageDischarge')) {
									graphic.attributes.gageDischarge = 'n.a.';
								}
								
							}
							
							reservoirsToggle.selected = true;
						}
					}
					
				}
			}

			private function addAttributeToGraphic(gageID:String, paramCode:String, paramValue:String, dateTime:String):void {
				for each (var graphic:Graphic in streamGageGraphicsLayer.graphicProvider) {
					if (gageID == graphic.attributes.GageID && paramCode == "00060") {
						graphic.attributes.Discharge = paramValue;
					} else if (gageID == graphic.attributes.GageID && paramCode == "00065") {
						graphic.attributes.gageGageHeight = paramValue;
						graphic.attributes.gageGhDateTime = dateTimeParse(dateTime);
					}
				}
				for each (var graphic:Graphic in reservoirGraphicsLayer.graphicProvider) {
					/*if (paramCode != "00065" && paramCode != "72120" && !graphic.attributes.hasOwnProperty('resLatestVolume')) {
						graphic.attributes.resLatestVolume = 'n.a.';
						graphic.attributes.resLVDateTime = 'n.a.';
					} else if (paramCode != "00065" && paramCode != "72022" && !graphic.attributes.hasOwnProperty('resLatestCapacity')) {
						graphic.attributes.resLatestCapacity = 'n.a.';
						graphic.attributes.resLCDateTime = 'n.a.';
					} else if (paramCode != "00065" && paramCode != "72022" && !graphic.attributes.hasOwnProperty('resElevation')) {
						graphic.attributes.resElevation = 'n.a.';
						graphic.attributes.resElevDateTime = 'n.a.';
					}*/
					
					if (gageID == graphic.attributes.ResID && paramCode == "00062") {
						graphic.attributes.resElevation = paramValue;
						graphic.attributes.resElevDateTime = dateTimeParse(dateTime);
					} else if (gageID == graphic.attributes.ResID && paramCode == "00065") {
						graphic.attributes.resGageHeight = paramValue;
						graphic.attributes.resGhDateTime = dateTimeParse(dateTime);
					} else if (gageID == graphic.attributes.ResID && paramCode == "62614") {
						graphic.attributes.resElevation = paramValue;
						graphic.attributes.resElevDateTime = dateTimeParse(dateTime);
					} else if (gageID == graphic.attributes.ResID && paramCode == "72022") {
						graphic.attributes.resLatestVolume = paramValue;
						graphic.attributes.resLVDateTime = dateTimeParse(dateTime);
					} else if (gageID == graphic.attributes.ResID && paramCode == "72120") {
						graphic.attributes.resLatestCapacity = paramValue;
						graphic.attributes.resLCDateTime = dateTimeParse(dateTime);
					} else if (gageID == graphic.attributes.ResID && paramCode == "72121") {
						graphic.attributes.resUsableCapacity = paramValue;
						graphic.attributes.resUCDateTime = dateTimeParse(dateTime);
					}  else if (gageID == graphic.attributes.DwnStreamGageID && paramCode == "00065") {
						graphic.attributes.gageGageHeight = paramValue;
						graphic.attributes.gageGhDateTime = dateTimeParse(dateTime);
					}
		
				}
				
				function dateTimeParse(dateTime:String):String {
					var dateTimeArray:Array = dateTime.split('T');
					var time:Array = dateTimeArray[1].split('.');
					
					var dateTimeString:String = dateTimeArray[0] + ', ' + time[0];
					
					return dateTimeString
				}
			}

			

			//Handles click requests for map layer info
    		private function onMapClick(event:MapMouseEvent):void
    		{
				trace(map.extent);
    			//queryGraphicsLayer.clear();
				//PopUpManager.removePopUp(_queryWindow);
   						    		    			 			
				var identifyParameters:IdentifyParameters = new IdentifyParameters();
				identifyParameters.returnGeometry = true;
				identifyParameters.tolerance = 4;
				identifyParameters.width = map.width;
				identifyParameters.height = map.height;
				identifyParameters.geometry = event.mapPoint;
				identifyParameters.mapExtent = map.extent;
				identifyParameters.spatialReference = map.spatialReference;
				
				var identifyTask:IdentifyTask = new IdentifyTask(resourceManager.getString( 'urls', 'streamgagesReservoirs'));
    		  	//identifyTask.execute(identifyParameters, new AsyncResponder(infoSingleResult, infoFault, new ArrayCollection([{eventX: event.stageX, eventY: event.stageY}])) );
					
			  	/*if (reservoirsToggle.selected && streamGagesToggle.selected) {
				  
				   	identifyTask.execute(identifyParameters, new AsyncResponder(infoSingleResult, infoFault, new ArrayCollection([{eventX: event.stageX, eventY: event.stageY}])) );
				   
			 	} else if (reservoirsToggle.selected) {
				
					identifyParameters.layerIds = [1];
				    identifyTask.execute(identifyParameters, new AsyncResponder(infoSingleResult, infoFault, new ArrayCollection([{eventX: event.stageX, eventY: event.stageY}])) );
					
			  	} else if (streamGagesToggle.selected) {

				    identifyParameters.layerIds = [0];
					identifyTask.execute(identifyParameters, new AsyncResponder(infoSingleResult, infoFault, new ArrayCollection([{eventX: event.stageX, eventY: event.stageY}])) );	
				}*/
				
			}
    		
			private function getSummaryTables(event:MouseEvent, index:int = 0):void {
				summaryTableIndex = index;
				
				_summaryWindow = PopUpManager.createPopUp(map, SummaryTables, false) as WiMInfoWindow;
				_summaryWindow.setStyle("skinClass", WiMInfoWindowSkin);
				_summaryWindow.x = event.stageX - _summaryWindow.width - 100;
				_summaryWindow.y = event.stageY;
				
				var resDataProvider:ArrayCollection = new ArrayCollection();
				for each (var graphic:Graphic in reservoirGraphicsLayer.graphicProvider) {
					//if (graphic.attributes.HAS_REALTIME == "1") {
						resDataProvider.addItem(graphic.attributes);
						trace(graphic.attributes.DownstreamGage);
					//}
				}
				
				var sortA:spark.collections.Sort = new spark.collections.Sort();
				var resSortField:spark.collections.SortField = new spark.collections.SortField();
				resSortField.name = "ResName";
				sortA.fields = [resSortField];
				resDataProvider.sort = sortA;
				resDataProvider.refresh();
				
				var strGageDataProvider:ArrayCollection = new ArrayCollection();
				for each (var graphic:Graphic in streamGageGraphicsLayer.graphicProvider) {
					//if (graphic.attributes.HAS_REALTIME == "1") {
						strGageDataProvider.addItem(graphic.attributes);
					//}
				}
				
				sortA = new spark.collections.Sort();
				resSortField = new spark.collections.SortField();
				resSortField.name = "NearestRes";
				sortA.fields = [resSortField];
				strGageDataProvider.sort = sortA;
				strGageDataProvider.refresh();
				
				_summaryWindow.data = new ArrayCollection([resDataProvider,strGageDataProvider]);
				_summaryWindow.addEventListener(CloseEvent.CLOSE, closePopUp);
			}

			public function numProperties(value:Object):int
			{
				var n:int = 0;
				for each(var p:Object in value) {
					n++;
				}
				return n;
			}

			private function queryFault(info:Object, token:Object = null):void
			{
				Alert.show(info.toString());
			} 
    		
    		
    		/* Query tooltip methods */
    		    	   		   		    		   
    		private function infoSingleResult(resultSet:Array, configObjects:ArrayCollection):void {		
				
				if (resultSet.length != 0) {
					
					var aGraphic:Graphic = resultSet[0].feature;
					PopUpManager.removePopUp(_queryWindow);
						
	    			if (resultSet[0].layerName == 'reservoirs') {
			
						_queryWindow = PopUpManager.createPopUp(map, ReservoirDataWindow, false) as WiMInfoWindow;
						aGraphic.symbol = circQuerySym;
						queryGraphicsLayer.add(aGraphic);
						
					} else if  (resultSet[0].layerName == 'downstream_gages') {
						
						_queryWindow = PopUpManager.createPopUp(map, StreamGagesDataWindow, false) as WiMInfoWindow;
						aGraphic.symbol = triQuerySym;
						queryGraphicsLayer.add(aGraphic);
					}
					_queryWindow.setStyle("skinClass", WiMInfoWindowSkin);
					_queryWindow.x = configObjects.getItemAt(0).eventX;
					_queryWindow.y = configObjects.getItemAt(0).eventY;
					_queryWindow.data = resultSet[0].feature.attributes;
					_queryWindow.addEventListener(CloseEvent.CLOSE, closePopUp);
				}
			}  

			
    		private function infoFault(info:Object, token:Object = null):void
    		{
    			Alert.show(info.toString());
    		} 


			public function closePopUp(event:CloseEvent):void {
				PopUpManager.removePopUp(event.currentTarget as WiMInfoWindow);
				queryGraphicsLayer.clear();
			}
    		   	
		 	/* End query tooltip methods */
		
		
    			
    		    		
    		private function baseSwitch(event:FlexEvent):void            
    		{                
				var tiledLayer:TiledMapServiceLayer = event.target as TiledMapServiceLayer;                
				if ((tiledLayer != null) && (tiledLayer.tileInfo != null) && (tiledLayer.id != "labelsMapLayer")) {
					map.lods = tiledLayer.tileInfo.lods;
				}
    		}
    		
    		
    		
    		
    		/* Geo-coding methods */
    		private function geoCode(searchCriteria:String):void
    		{
				
				
				if (geocoder.searchValue.text == geocoder.searchHint || geocoder.searchValue.text == null || geocoder.searchValue.text == '') {
					Alert.show("Please enter an address into the Find Location tool.");
				} else {						
				veGeocoder.addressToLocations(geocoder.searchValue.text, new AsyncResponder(onResult, onFault));
				}
				
				function onResult(results:Array, token:Object = null):void
				{
					if (results.length > 0)
					{
						var veResult:VEGeocodeResult = results[0];
						map.extent = WebMercatorUtil.geographicToWebMercator(veResult.bestView) as Extent;
						//map.extent = veResult.bestView;
					}
					else
					{
						Alert.show("Could not find " + geocoder.searchValue.text + ". Please try again");
					}
				}
    		}
    					

    		private function onFault(info:Object, token:Object = null):void
    		{
    			Alert.show("Error: " + info.toString(), "problem with Locator");
    		}
    		
    		/* End geo-coding methods */

			/* Dynamic Legend methods */
			private function legendResults(resultSet:ResultEvent, aLegendContainer:SkinnableContainer, layerIDs:ArrayCollection, singleTitle:String = null):void
			{
				
				if (resultSet.statusCode == 200) {
					//Decode JSON result
					var decodeResults:Object = com.esri.ags.utils.JSON.decode(resultSet.result.toString());
					var legendResults:Array = decodeResults["layers"] as Array;
					//Clear old legend
					aLegendContainer.removeAllElements();	
					
					//if single title is specified use that
					if (singleTitle != null || aLegendContainer.id == 'siteLegend') {
						//Add outline with flash effect   
						var singleGroupDescription:spark.components.Label = new spark.components.Label();
						singleGroupDescription.setStyle("verticalAlign", "middle");
						singleGroupDescription.setStyle("fontSize", "11");
						singleGroupDescription.height = 20;
						singleGroupDescription.top = 10;
						aLegendContainer.addElement(	singleGroupDescription );
					}
					
					for(var i:int = 0; i < legendResults.length; i++) {											
						if (layerIDs.contains(legendResults[i]["layerId"])) {
							//Add outline with flash effect   
							var groupDescription:spark.components.Label = new spark.components.Label();
							
							//if singleTitle is not specified, Add name with USGS capitalization, first letter only
							if (singleTitle == null) {
								var layerName:String = legendResults[i]["layerName"];
								groupDescription.text = layerName; //.charAt(0).toUpperCase() + layerName.substr(1, layerName.length-1).toLowerCase();
								//TODO: Move this to a single style
								groupDescription.setStyle("verticalAlign", "middle");
								groupDescription.setStyle("fontSize", "11");
								groupDescription.width = 300;
								groupDescription.top = 10;
								aLegendContainer.addElement(	groupDescription );
							}
							
							for each (var aLegendItem:Object in legendResults[i]["legend"]) {
								//Decode base 64 image data
								var b64Decoder:Base64Decoder = new Base64Decoder();							
								b64Decoder.decode(aLegendItem["imageData"].toString());
								//Make new image for decoded bytes
								var legendItemImage:Image = new Image();
								legendItemImage.load( b64Decoder.toByteArray() );
								var aLabel:String = aLegendItem["label"];
								//If singleTitle is specified and there is a single legend item with no label, use the layerName 
								if ((singleTitle != null) && (aLabel.length == 0) && ((legendResults[i]["legend"] as Array).length <= 1)) { aLabel = legendResults[i]["layerName"]; }
								//Use USGS sentence capitalization on labels
								aLabel = aLabel.charAt(0).toUpperCase() + aLabel.substr(1, aLabel.length-1).toLowerCase();								
								var legendItem:HGroup = 
									makeLegendItem( 
										legendItemImage, 
										aLabel
									);
								legendItem.paddingLeft = 20;
								aLegendContainer.addElement( legendItem );
								
							}			
						}
					} 
					
					
				}  else {
					Alert.show("No legend data found.");
				}		
				
				//Remove wait cursor
				CursorManager.removeBusyCursor();
			}
			
			private function makeLegendItem(swatch:UIComponent, label:String):HGroup {
				var container:HGroup = new HGroup(); 
				var layerDescription:spark.components.Label = new spark.components.Label();
				layerDescription.text = label;
				layerDescription.setStyle("verticalAlign", "middle");
				layerDescription.percentHeight = 100;
				container.addElement(swatch);
				container.addElement(layerDescription);
				
				return container;
			}

			private function openTool():void
			{
				if (_queryWindow && queryGraphicsLayer.graphicProvider.length > 0) {
					return;
				} else {
					_queryWindow = PopUpManager.createPopUp(map, ReservoirDataWindow, false) as WiMInfoWindow;
					_queryWindow.setStyle("skinClass", WiMInfoWindowSkin);
					_queryWindow.x = 200;
					_queryWindow.y = 200;
				}

    		
			}		
    		
    	
    		