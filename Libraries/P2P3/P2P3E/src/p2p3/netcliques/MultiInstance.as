/**
* Single device, multi-instance clique implementation via LocalConnection.
*
* (C)opyright 2014 to 2017
*
* This source code is protected by copyright and distributed under license.
* Please see the root LICENSE file for terms and conditions.
*
*/

package p2p3.netcliques {
	
	import flash.events.Event;
	import flash.net.LocalConnection;
	import flash.events.EventDispatcher;
	import flash.utils.ByteArray;
	import p2p3.interfaces.INetClique;
	import p2p3.interfaces.INetCliqueMember;
	import p2p3.netcliques.NetCliqueMember;
	import p2p3.interfaces.IPeerMessage;
	import p2p3.events.NetCliqueEvent;
	import flash.utils.getTimer;
	import org.cg.DebugView;
	import p2p3.PeerMessage;
	import flash.external.ExternalInterface;
	import flash.utils.setTimeout;
	
	public class MultiInstance extends EventDispatcher implements INetClique {
		
		public static const connectionNamePref:String = "_clique_localMI"; //local connection name prefix		
		private var _localConnection:LocalConnection = null;	
		private var _segmentID:String = null; //optional segment ID used for segregated communications ("newRoom" functionality)
		private var _connectionIndex:uint = 0; //current node index
		private var _localPeerID:String = null; //local peer ID generated by generateConnectionID
		private var _connected:Boolean = false; //is clique connected?
		private var _localPeerInfo:INetCliqueMember = null; //local (self) peer info
		private var _connectedPeers:Vector.<INetCliqueMember> = new Vector.<INetCliqueMember>(); //all currently connected peers
		private var _connectionNamesMap:Vector.<Object> = new Vector.<Object>(); //objects currently contain "peerID" and "connectionName" properties
		private var _rooms:Vector.<INetClique> = new Vector.<INetClique>(); //registered segregated rooms as INetClique implementation instances
		private var _parentClique:INetClique = null; //reference to parent INetClique implementation instance; if null this is the top-most parent
		
		/**
		 * Creates a new instance.
		 */
		public function MultiInstance(parentClique:INetClique = null, segmentID:String = null) {			
			_parentClique = parentClique;
			this._segmentID = segmentID;			
			if (this._segmentID != null) {				
				//allow time to create any necessary listeners
				setTimeout(this.connect, 500);				
			}
		}
		
		/**
		 * True if the LocalConnection clique is currently connected.
		 */
		public function get connected():Boolean {
			return (_connected);
		}
		
		/**
		 * A vector array of INetCliqueMember implementations representing currently connected peers.
		 */
		public function get connectedPeers():Vector.<INetCliqueMember> {
			return (_connectedPeers);
		}
		
		/**
		 * An INetCliqueMember implementation containing local (self) peer information.
		 */
		public function get localPeerInfo():INetCliqueMember {			
			return (_localPeerInfo);
		}
		
		/**
		 * The local (self) peer ID associated with this instance.
		 */
		public function get localPeerID():String {
			if ((_localPeerID == null) || (_localPeerID == "")) {
				if (_parentClique != null) {
					_localPeerID = MultiInstance(_parentClique).localPeerID;
				} else {
					_localPeerID = generateConnectionID();
				}
			}
			return (_localPeerID);
		}
		
		/**
		 * @return A vector array of segragated INetClique implementation instances (MultiInstance), or rooms, registered with
		 * this instance.
		 */
		public function get rooms():Vector.<INetClique> {
			return (this._rooms);
		}
		
		/**
		 * @return A reference to the parent INetClique implementation instance, or null if this is the parent (top-most) instance.
		 */
		public function get parentClique():INetClique {
			return (this._parentClique);
		}
		
		/**
		 * Handler for emulated peer disconnections.
		 * 
		 * @param	peerID The peer ID being disconnected. Once disconnected the peer ID will be invalid for
		 * any subsequent calls.
		 */
		public function onDisconnect(peerID:String):void {
			var event:NetCliqueEvent = new NetCliqueEvent(NetCliqueEvent.PEER_DISCONNECT);
			var memberObj:INetCliqueMember = new NetCliqueMember(peerID);
			event.memberInfo = memberObj;
			//mimics RTMFP functionality where only parent instance dispatched CONNECT, DISCONNECT, and related events
			if (_parentClique == null) {
				dispatchEvent(event);
			} else {
				_parentClique.dispatchEvent(event);
			}
		}		
	
		/**
		 * Sends a message only to a specific connected peer.
		 * 
		 * @param	peers A connected peer, as an INetCliqueMember implementations to send the message to.
		 * @param	msgObj The message to send to the specified peer.
		 * 
		 * @return True if the message could be sent, false otherwise.
		 */
		public function sendToPeer(peer:INetCliqueMember, msgObj:IPeerMessage):Boolean {
			msgObj.addSourcePeerID(localPeerID);			
			var targetConnectionName:String = getConnectionName(peer.peerID);				
			if (targetConnectionName != null) {					
				_localConnection.send(targetConnectionName, "message", connectionName, peer.peerID, msgObj.serializeToAMF3(true));
				return (true);
			}
			return (false);
		}
		
		/**
		 * Sends a message only to a specific list of connected peers.
		 * 
		 * @param	peers A vector array of connected peers, as INetCliqueMember implementations, to send the message to.
		 * @param	msgObj The message to send to the specified peers.
		 * 
		 * @return A vector array containing boolean values for each supplied peer, in order, denoting whether or
		 * not the message could be sent. If true, the message could be sent to the specific peer, false otherwise.
		 */
		public function sendToPeers(peers:Vector.<INetCliqueMember>, msgObj:IPeerMessage):Vector.<Boolean> {
			var successes:Vector.<Boolean> = new Vector.<Boolean>();
			msgObj.addSourcePeerID(localPeerID);
			for (var count:int = 0; count < peers.length; count++) {
				var currentPeer:INetCliqueMember = peers[count];				
				var targetConnectionName:String = getConnectionName(currentPeer.peerID);				
				if (targetConnectionName != null) {					
					_localConnection.send(targetConnectionName, "message", connectionName, currentPeer.peerID, msgObj.serializeToAMF3(true));
					successes.push(true);
				} else {
					successes.push(false);
				}
			}
			return (successes);
		}
		
		/**
		 * Broadcasts a message to all connected peers.
		 * 
		 * @param	msgObj The message to broadcast.
		 * 
		 * @return True if the message could be successfully broadcast, false otherwise (for example, not peers to broadcast to).
		 */
		public function broadcast(msgObj:IPeerMessage):Boolean {			
			if (_connectedPeers == null) {
				return (false);
			}
			if (_connectedPeers.length == 0) {
				return (false);
			}
			if ((msgObj.targetPeerIDs == "") || (msgObj.targetPeerIDs == null)) {
				msgObj.targetPeerIDs = "*";
			}
			msgObj.addSourcePeerID(localPeerID);
			for (var count:int = 0; count < _connectedPeers.length; count++) {
				var currentPeer:INetCliqueMember = _connectedPeers[count];				
				var targetConnectionName:String = getConnectionName(currentPeer.peerID);				
				if (targetConnectionName != null) {					
					_localConnection.send(targetConnectionName, "message", connectionName, currentPeer.peerID, msgObj.serializeToAMF3(true));
				}
			}
			return (true);
		}
		
		/**
		 * Initializes and connects the clique.
		 * 
		 * @param	... args Optional arguments. May include:
		 * [0] - Segment identifier for segregated communication groups. Default (main) group has none.
		 * 
		 * @return True if the clique connection was successfully initiated, false if the initiated connection attempt failed (already
		 * connected, for example).
		 */
		public function connect(... args):Boolean {
			var success:Boolean = false;
			var event:NetCliqueEvent = null;
			try {
				if (LocalConnection.isSupported) {
					_localConnection = new LocalConnection();
					_localConnection.client = this;
					_localConnection.allowDomain("*");
					_localConnection.allowInsecureDomain("*");					
					_localConnection.connect(connectionName);
					_localPeerInfo = new NetCliqueMember(localPeerID);
					var connNameMap:Object = new Object();
					connNameMap.peerID = localPeerID;
					connNameMap.connectionName = connectionName;
					_connectionNamesMap.push(connNameMap);
					_connected = true;					
					success = true;
					sendStartupHandshake();					
					event = new NetCliqueEvent(NetCliqueEvent.CLIQUE_CONNECT);
					if (ExternalInterface.available) {
						//unreliable - is there a better way?
						ExternalInterface.addCallback("_onunloadcb", disconnect);		
						var	jsExecuteCallBack:String = "document.getElementsByName('"+ExternalInterface.objectID+"')[0]._onunloadcb();return('');";
						var jsBindEvent:String = "function(){window.unload=function(){"+jsExecuteCallBack+"};}";						
						ExternalInterface.call(jsBindEvent);
					}
				} else {					
					event = new NetCliqueEvent(NetCliqueEvent.CLIQUE_ERROR);
					success = false;
				}
			} catch (err:*) {
				DebugView.addText(err);
				_connected = false;
				_localConnection = null;
				if (err.errorID == 2082) {					
					//connection at this index already exists, try next one
					_connectionIndex++;
					connect.call(this, args);
					success = true;
				} else {
					DebugView.addText(err);
					event = new NetCliqueEvent(NetCliqueEvent.CLIQUE_ERROR);					
					success = false;
				}
			} finally {	
				if (event != null) {					
					dispatchEvent(event);					
				}				
				return (success);
			}
		}		
		
		/**
		 * Disconnects the current LocalConnection clique connection.
		 * 
		 * @return True if the clique could be disconnected, false if the clique was not connected.
		 */
		public function disconnect():Boolean {			
			if (_localConnection != null) {
				sendDisconnect();
				_localConnection.close();
				_localConnection = null;
				_connected = false;
				return (true);
			} else {
				return (false);
			}
		}		
		
		/**
		 * Handler for incoming LocalConnection handshakes.
		 * 
		 * @param	handshakeInfo The source/sending handshake information object being received.
		 */
		public function handshake(handshakeInfo:Object):void {			
			if (peerConnected(handshakeInfo.peerID) == false) {				
				var handshakeObject:Object = generateHandshakeObject();
				var newMember:NetCliqueMember = new NetCliqueMember(handshakeInfo.peerID);
				_connectedPeers.push(newMember);
				var connNameMap:Object = new Object();
				connNameMap.peerID = handshakeInfo.peerID;
				connNameMap.connectionName = handshakeInfo.connectionName;
				_connectionNamesMap.push(connNameMap);
				_localConnection.send(handshakeInfo.connectionName, "handshake", handshakeObject);
				var event:NetCliqueEvent = new NetCliqueEvent(NetCliqueEvent.PEER_CONNECT);
				event.memberInfo = newMember;
				dispatchEvent(event);
			} else {
				//member is already connected so ignore
			}
		}
				
		/**
		 * Creates a new room or segregated INetClique implementation instance (MultiInstance).
		 * 
		 * @param	options Initialization options object to pass to the new MultiInstance instance's constructor.
		 * 
		 * @return A newly created, segregated INetClique implementation (MultiInstance), or room.
		 */
		public function newRoom(options:Object):INetClique {
			if (this.parentClique != null) {
				return (this.parentClique.newRoom(options));
			}
			var newRoom:MultiInstance = new MultiInstance(this, options.groupName);
			this._rooms.push(newRoom);
			return (newRoom);
		}
		
		/**
		 * Handler for incoming LocalConnection messages.
		 * 
		 * @param	connectionID The unique source/sending LocalConnection connection ID.
		 * @param	peerID The unique source/sending peer ID.
		 * @param	messageObj The AMF3-encoded message being received.
		 */
		public function message(connectionID:String, peerID:String, messageObj:ByteArray):void {
			var incomingMsg:PeerMessage = new PeerMessage(messageObj);
			var event:NetCliqueEvent = new NetCliqueEvent(NetCliqueEvent.PEER_MSG);
			event.memberInfo = getMemberInfo(peerID);
			event.message = incomingMsg;
			dispatchEvent(event);
		}
		
		/**
		 * Method invoked when a child MultiInstance instance is about to be destroyed.
		 * 
		 * @param	room The reference to the child room or INetClique implementation instance (MultiInstance) about to be destroyed.
		 */
		public function onChildDestroy(room:INetClique):void {
			if (this.parentClique != null) {
				try {
					this.parentClique["onChildDestroy"](this);
				} catch (err:*) {					
				}
			}
			if (this._rooms != null) {
				for (var count:int = 0; count < this._rooms.length; count++) {
					if (this._rooms[count] == room) {
						this._rooms.splice(count, 1);
						return;
					}
				}
			}
		}
		
		/**
		 * Method invoked when the instance is about to be removed from memory. If this is a child instance, the parent's "onChildDestroy"
		 * is invoked first.
		 */
		public function destroy():void {
			if (this.parentClique != null) {
				try {
					this.parentClique["onChildDestroy"](this);
				} catch (err:*) {					
				}
			}
			this._localPeerID = "";
			this.localPeerInfo.peerID = "";
			if (_localConnection != null) {
				_localConnection.close();
				_localConnection = null;
			}
		}
		
		/**
		 * Finds the unique Localconnection connection name for a specific peer ID.
		 * 
		 * @param	targetPeerID The peer ID for which to find a connection name.
		 * 
		 * @return The connection name for the specified peer ID, or null if no match can be found.
		 */
		protected function getConnectionName(targetPeerID:String):String {
			for (var count:int = 0; count < _connectedPeers.length; count++) {
				var currentPeer:INetCliqueMember = _connectedPeers[count];
				for (var count2:int = 0; count2 < _connectionNamesMap.length; count2++) {
					var currentMap:Object = _connectionNamesMap[count2];
					if (currentMap.peerID == targetPeerID) {
						return (currentMap.connectionName);
					}
				}
			}
			return (null);		
		}		
		
		/**
		 * Sends an initial startup handshake message to all connected peers.
		 */
		protected function sendStartupHandshake():void {			
			var handshakeObj:Object = generateHandshakeObject();
			for (var count:uint = 0; count < _connectionIndex; count++) {
				try {
					if (this._segmentID != null) {
						var currentConnectionName:String = connectionNamePref +"_"+ this._segmentID +"_"+ String(count);	
					}  else {
						currentConnectionName = connectionNamePref + String(count);
					}
					_localConnection.send(currentConnectionName, "handshake", handshakeObj);
				} catch (err:* ) {					
				}
			}
		}
		
		/**
		 * Checks whether or not a specific peer ID is connected.
		 * 
		 * @param	peerID The peer ID to check.
		 * 
		 * @return True if the specified peer is currently connected, false otherwise.
		 */
		protected function peerConnected(peerID:String):Boolean {
			if (_connectedPeers == null) {
				_connectedPeers = new Vector.<INetCliqueMember>();
			}
			for (var count:int = 0; count < _connectedPeers.length; count++) {
				if (_connectedPeers[count].peerID == peerID) {
					return (true);
				}
			}
			return (false);
		}
		
		/**
		 * Emulates a local disconnection by sending a disconnect message to all connected peers.
		 */
		protected function sendDisconnect():void {
			for (var count:int = 0; count < _connectedPeers.length; count++) {
				var currentPeer:INetCliqueMember = _connectedPeers[count];				
				var targetConnectionName:String = getConnectionName(currentPeer.peerID);				
				if (targetConnectionName != null) {					
					_localConnection.send(targetConnectionName, "onDisconnect", localPeerID);
				}
			}			
		}		
		
		/**
		 * @return A unique connection ID for this LocalConnection peer. The ID is
		 * based on the current system date and time and elapsed time since startup. Since every
		 * instance of this class will execute on the same device it should be impossible for
		 * any two instances to have exactly the same ID.
		 */
		protected function generateConnectionID():String {
			var IDString:String = new String();
			var dateObj:Date = new Date();
			IDString = String(dateObj.getFullYear());
			IDString += String(dateObj.getMonth());
			IDString += String(dateObj.getDay());
			IDString += String(dateObj.getHours());
			IDString += String(dateObj.getMinutes());
			IDString += String(dateObj.getSeconds());
			IDString += String(dateObj.getMilliseconds());
			IDString += String(getTimer());
			return (IDString);
		}
		
		/**
		 * Generates a handshake information object, usually sent after an initial peer connection is established.
		 * 
		 * @return A handshake information object containing the local properties "peerID" and "connectionName".
		 */
		protected function generateHandshakeObject():Object {
			var returnObj:Object = new Object();
			//structure must match that expected in handshake method
			returnObj.peerID = localPeerID;
			returnObj.connectionName = connectionName;
			return (returnObj);
		}		
		
		/**
		 * The unique LocalConnection connection name currently being used by this instance.
		 */
		private function get connectionName():String {
			if (this._segmentID != null) {
				return (connectionNamePref +"_"+ this._segmentID +"_"+ String(_connectionIndex));	
			} 
			return (connectionNamePref + String(_connectionIndex));
		}
		
		
		/**
		 * Returns an INetCliqueMember implementation object for a matching peer ID.
		 * 
		 * @param	peerID The peer ID to search for.
		 * 
		 * @return An INetCliqueMember implementation for the supplied peer ID, or null if none can be found.
		 */
		private function getMemberInfo(peerID:String):INetCliqueMember {
			if (peerID == _localPeerID) {
				return (_localPeerInfo);
			}
			for (var count:int = 0; count < _connectedPeers.length; count++) {
				var currentMember:INetCliqueMember = _connectedPeers[count];
				if (currentMember.peerID == peerID) {
					return (currentMember);
				}
			}
			return (null);
		}
	}
}