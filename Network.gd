extends Node

# The port we will listen to
const PORT = 52450
const characters = '0123456789ABCDEF'

const MAX_PEERS = 2000

const NO_PEERS_RESTART_TIME = 0.25 * 60 * 60

# Our WebSocketServer instance
var _server = WebSocketServer.new()
var restart_timer = Timer.new()

var matches = {}
var players = {}

func _ready():
	# Connect base signals to get notified of new client connections,
	# disconnections, and disconnect requests.
#	_server.connect("client_connected", self, "_connected")
#	_server.connect("client_disconnected", self, "_disconnected")
#	_server.connect("client_close_request", self, "_close_request")
	
	_server.connect("peer_connected", self, "_on_peer_connected")
	_server.connect("peer_disconnected", self, "_on_peer_disconnected")
	
	add_child(restart_timer)
	restart_timer.connect("timeout", self, "_on_restart_timer_timeout")
	randomize()

	var err = _server.listen(PORT, PoolStringArray(["binary"]), true)
	if err != OK:
		print("Unable to start server")
		set_process(false)
	get_tree().set_network_peer(_server)
	restart_timer.start(NO_PEERS_RESTART_TIME)

func _on_restart_timer_timeout():
	var num_peers = get_tree().multiplayer.get_network_connected_peers().size()
	print("Connected peers: " + str(num_peers))
#	if num_peers == 0:
#		print("No users connected. restarting...")
#		get_tree().quit()

func _on_peer_connected(id):
#	print("Client %d connected" % [id])
	players[id] = Player.new(id)
	
#	rpc_id(id, "test_relay")


func _on_peer_disconnected(id):
#	print("Client %d disconnected" % [id])
	if matches.has(players[id].match_id):
		var match_ = matches[players[id].match_id]
		if match_.host == players[id]:
			match_.host = null
		if match_.client == players[id]:
			match_.client = null
		if match_.host == null and match_.client == null:
#			print("removing match %s" % [match_.id])
			matches.erase(match_.id)
	players.erase(id)

func generate_match_id():
	var id = ""
	for _i in range(4):
		id += characters[randi() % len(characters)]
	if id in matches:
		return generate_match_id()
	return id

func error(id, error_type):
	var errors = {
		"username_too_long": "Username too long. Please try again with a shorter username.",
		"server_full": "Dojo full.",
	}
	if error_type in errors:
		rpc_id(id, "server_error", errors[error_type])
	else:
		rpc_id(id, "server_error", "Unknown server error.")

remote func create_match(player_name, public):
	var id = get_tree().get_rpc_sender_id()
	if len(player_name) > 64:
		error(id, "username_too_long")
	if players.has(id):
		var match_id = generate_match_id()
		players[id].match_id = match_id
		players[id].username = player_name
		matches[match_id] = Match.new(match_id, players[id])
		matches[match_id].public = public
		print("created match %s" % [match_id])
		rpc_id(id, "receive_match_id", match_id)

remote func relay(function, arg):
	var id = get_tree().get_rpc_sender_id()
	if players.has(id):
		var host = players[id]
		var args
		if arg == null:
			args = [function]
		else:
			args = [function] + (arg if arg is Array else [arg])
			
		if host.opponent:
#			print("relaying: " + function + " from " + str(id) + " - " + str(arg))
			callv("rpc_id", [host.opponent.id] + args)

remote func player_join_game(player_name, room_code):
	var id = get_tree().get_rpc_sender_id()
	if len(player_name) > 64:
		error(id, "username_too_long")
		return
	room_code = room_code.to_upper()
	if matches.has(room_code) and players.has(id):
		var match_ = matches[room_code]
		var player = players[id]
		if match_.client != null:
			rpc_id(id, "room_join_deny", "Room full.")
			return
		match_.client = player
		match_.host.opponent = player
		player.opponent = match_.host
		player.match_id = room_code
		player.username = player_name
		match_.started = true
#		print("player %d joined match %s" % [id, room_code])
		rpc_id(id, "room_join_confirm")
		rpc_id(id, "player_connected_relay")
		rpc_id(match_.host.id, "player_connected_relay")
	else:
		rpc_id(id, "room_join_deny", "Room with code %s does not exist." % [room_code])
		return

func check_server_full(id):
#	if get_tree().multiplayer.get_network_connected_peers().size() > MAX_PEERS:
#		error(id, "server_full")
#		yield(get_tree().create_timer(1.0), "timeout")
#		_server.disconnect_peer(id)
#		return true
	return false

remote func fetch_match_list():
#	print("fetching match list")
	var id = get_tree().get_rpc_sender_id()
	if check_server_full(id):
		return
	var list = []
	for match_ in matches.values():
		if !match_.started and match_.public:
			list.append(match_.to_lobby_dict())
		pass
	rpc_id(id, "receive_match_list", list)

remote func fetch_player_count():
#	print("fetching match list")
	var id = get_tree().get_rpc_sender_id()
	var player_count = get_tree().multiplayer.get_network_connected_peers().size() - 1
	rpc_id(id, "receive_player_count", player_count)
