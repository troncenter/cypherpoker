/**
* Events dispatched by the RochambeauGame class.
* 
* (C)opyright 2014 to 2017
*
* This source code is protected by copyright and distributed under license.
* Please see the root LICENSE file for terms and conditions.
*
*/

package p2p3.events {
	
	import flash.events.Event;
	
	public class RochambeauGameEvent extends Event 	{
		
		//The game phase of the RochambeauGame instance has just changed.		
		public static const PHASE_CHANGE:String = "Event.RochambeauGameEvent.PHASE_CHANGE";
		//Validation of supplied profile prime value has failed.
		public static const VALIDATION_ERROR:String = "Event.RochambeauGameEvent.VALIDATION_ERROR";
		
		public function RochambeauGameEvent(type:String, bubbles:Boolean=false, cancelable:Boolean=false) {
			super(type, bubbles, cancelable);			
		}		
	}
}