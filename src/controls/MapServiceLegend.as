// 08.02.12 - NE - Added properties for specifying legend title and a filter to show only certain swatches and attributes in legend. 
// 02.23.12 - NE - Created.

package controls
{
	import com.esri.ags.Map;
	import com.esri.ags.layers.ArcGISDynamicMapServiceLayer;
	import com.esri.ags.utils.JSON;
	
	import controls.skins.MapServiceLegend;
	
	import mx.collections.ArrayCollection;
	import mx.collections.IList;
	import mx.controls.Alert;
	import mx.controls.Image;
	import mx.core.UIComponent;
	import mx.events.FlexEvent;
	import mx.managers.CursorManager;
	import mx.rpc.events.ResultEvent;
	import mx.rpc.http.HTTPService;
	import mx.utils.Base64Decoder;
	
	import spark.components.HGroup;
	import spark.components.SkinnableContainer;
	
	public class MapServiceLegend extends spark.components.SkinnableContainer
	{
		private var _map:Map;
		
		private var _serviceLayer:ArcGISDynamicMapServiceLayer;
		
		private var _legendWidth:Number;
		
		private var _legendTitle:String;
		
		private var _legendFilter:Array = null;
		
		private var _needsUpdates:Boolean = false;
		
		public var aLegendService:HTTPService;
		
		public var aLegend:SkinnableContainer;
		
		[Bindable]
		public function get map():Map {
			return _map;
		}
		
		public function set map(m:Map):void {
			_map = m;		
		}
		
		[Bindable]
		public function get serviceLayer():ArcGISDynamicMapServiceLayer {
			return _serviceLayer;
		}
		
		public function set serviceLayer(sl:ArcGISDynamicMapServiceLayer):void {
			_serviceLayer = sl;
		}
		
		[Bindable]
		public function get legendWidth():Number {
			return _legendWidth;
		}
		
		public function set legendWidth(lw:Number):void {
			_legendWidth = lw;
		}
		
		[Bindable]
		public function get legendTitle():String {
			return _legendTitle;
		}
		
		public function set legendTitle(lt:String):void {
			_legendTitle = lt;
		}
		
		[Bindable]
		public function get legendFilter():Array {
			return _legendFilter;
		}
		
		public function set legendFilter(lf:Array):void {
			_legendFilter = lf;
		}
		
		[Bindable]
		public function get needsUpdates():Boolean {
			return _needsUpdates;
		}
		
		public function set needsUpdates(nu:Boolean):void {
			_needsUpdates = nu;
		}
		
		override public function stylesInitialized():void {  
			super.stylesInitialized();
			this.setStyle("skinClass",Class(controls.skins.MapServiceLegend));
		}
		
		/* Dynamic Legend methods */
		public function legendResults(resultEvent:ResultEvent, singleTitle:String = null):void
		{
			
			if (resultEvent.statusCode == 200) {
				//Decode JSON result
				var decodeResults:Object = com.esri.ags.utils.JSON.decode(resultEvent.result.toString());
				var legendResults:Array = decodeResults["layers"] as Array;
				//Clear old legend
				aLegend.removeAllElements();	
				
				//if single title is specified use that
				if (singleTitle != null || aLegend.id == 'siteLegend') {
					//Add outline with flash effect   
					var singleGroupDescription:spark.components.Label = new spark.components.Label();
					singleGroupDescription.setStyle("verticalAlign", "middle");
					singleGroupDescription.setStyle("fontSize", "11");
					singleGroupDescription.height = 20;
					singleGroupDescription.top = 10;
					aLegend.addElement(	singleGroupDescription );
				}
				
				if (legendResults != null) {
					for(var i:int = 0; i < legendResults.length; i++) {									
						if (serviceLayer.visibleLayers != null && itemContained(serviceLayer.visibleLayers, legendResults[i]["layerId"])) { //&& serviceLayer.visibleLayers.contains(legendResults[i]["layerId"])) {
							//Add outline with flash effect   
							var groupDescription:spark.components.Label = new spark.components.Label();
							
							//if singleTitle is not specified, Add name with USGS capitalization, first letter only
							if (singleTitle == null) {
								if (legendTitle == null && legendResults[i]["layerName"] != "FWS Refuge Labels") {
									var layerName:String = legendResults[i]["layerName"];
								} else {
									var layerName:String = legendTitle;
								}
								groupDescription.text = layerName; //.charAt(0).toUpperCase() + layerName.substr(1, layerName.length-1).toLowerCase();
								//TODO: Move this to a single style
								groupDescription.setStyle("verticalAlign", "middle");
								groupDescription.setStyle("fontSize", "11");
								groupDescription.setStyle("fontWeight", "bold");
								groupDescription.top = 10;
								groupDescription.width = legendWidth-20;
								aLegend.addElement(	groupDescription );
							}
							
							for each (var aLegendItem:Object in legendResults[i]["legend"]) {
								//Decode base 64 image data
								if (legendFilter != null) {
									var j:int;
									for (j = 0; j < legendFilter.length; j++) {
										if (legendFilter[j] == aLegendItem["label"]) {
											legendItemCreation();
										}
									}
								} else {
									legendItemCreation();
								}
								
								function legendItemCreation():void {
									var b64Decoder:Base64Decoder = new Base64Decoder();							
									b64Decoder.decode(aLegendItem["imageData"].toString());
									//Make new image for decoded bytes
									var legendItemImage:Image = new Image();
									legendItemImage.load( b64Decoder.toByteArray() );
									var aLabel:String = aLegendItem["label"];
									//If singleTitle is specified and there is a single legend item with no label, use the layerName 
									if ((singleTitle != null) && (aLabel.length == 0) && ((legendResults[i]["legend"] as Array).length <= 1)) { aLabel = legendResults[i]["layerName"]; }
									//Use USGS sentence capitalization on labels
									//aLabel = aLabel.charAt(0).toUpperCase() + aLabel.substr(1, aLabel.length-1).toLowerCase();								
									var legendItem:HGroup = 
										makeLegendItem( 
											legendItemImage, 
											aLabel
										);
									legendItem.paddingLeft = 5;
									if (legendResults[i]["layerName"] != "FWS Refuge Labels") {
										aLegend.addElement( legendItem );
									}
									
								}
								
							}	
							
						}
					} 
				}
				
				
			}  else {
				Alert.show("No legend data found.");
			}		
			
			//Remove wait cursor
			CursorManager.removeBusyCursor();
		}
		
		private function itemContained(list:IList, layerId:String):Boolean {
			var itemIsContained:Boolean = false;
			
			for (var i:int=0; i < list.length; i++) {
				if (list[i] == layerId) {
					itemIsContained = true;
				} 
			}
			
			return itemIsContained;
		}
		
		private function makeLegendItem(swatch:UIComponent, label:String):HGroup {
			var container:HGroup = new HGroup(); 
			var layerDescription:spark.components.Label = new spark.components.Label();
			layerDescription.text = label;
			layerDescription.setStyle("verticalAlign", "middle");
			layerDescription.percentHeight = 100;
			
			//Code added for layer labels that need to wrap text
			layerDescription.width = this.legendWidth - swatch.width - 100;
			container.paddingTop = 5;
			container.paddingBottom = 5;
			//End of that code
			
			container.addElement(swatch);
			container.addElement(layerDescription);
			
			return container;
		}
		
		public function getLegends(event):void {
			if (aLegendService != null) {
				aLegendService.send();
			}
		}
		
		public function queryFault(info:Object, token:Object = null):void
		{
			Alert.show(info.toString());
		} 
		
	}
}