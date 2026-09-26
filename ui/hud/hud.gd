extends CanvasLayer
## Minimal in-game HUD: health, collectibles, equipped spell, interaction
## prompt, notifications, connection status. Reads player components via the
## local_player_spawned event; never drives gameplay.

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _fragments_label: Label = %FragmentsLabel
@onready var _spell_label: Label = %SpellLabel
@onready var _cooldown_bar: ProgressBar = %CooldownBar
@onready var _prompt_label: Label = %PromptLabel
@onready var _notification_label: Label = %NotificationLabel
@onready var _status_label: Label = %StatusLabel
@onready var _crosshair: Control = %Crosshair

const FRAGMENT_ID := &"arcane_fragment"

var _player: Node
var _caster: SpellCaster
var _notification_timer: float = 0.0
var _focused: Interactable
var _status: int = NetworkManager.Status.OFFLINE
var _status_message: String = ""


func _ready() -> void:
	GameEvents.local_player_spawned.connect(_bind_player)
	GameEvents.collectible_collected.connect(_on_collectible_collected)
	GameEvents.collectible_total_changed.connect(_on_total_changed)
	GameEvents.notification_requested.connect(show_notification)
	GameEvents.spell_learned.connect(_on_spell_learned)
	NetworkManager.status_changed.connect(_on_status_changed)
	_prompt_label.visible = false
	_notification_label.visible = false
	_update_fragments()
	_on_status_changed(NetworkManager.status, "")
	_on_spell_learned(null)


func _process(delta: float) -> void:
	if _caster != null and _caster.equipped_spell != null:
		var cd := _caster.equipped_spell.cooldown
		_cooldown_bar.value = 1.0 - (_caster.cooldown_remaining / cd if cd > 0.0 else 0.0)
	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			_notification_label.visible = false


func _bind_player(player: Node) -> void:
	_player = player
	var health: Health = player.health
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current, health.max_health)
	_caster = player.spell_caster
	_caster.spell_changed.connect(_on_spell_learned)
	_on_spell_learned(_caster.equipped_spell)
	var interaction: InteractionController = player.interaction_controller
	interaction.focus_changed.connect(_on_focus_changed)


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func _on_collectible_collected(_definition: Resource, _total: int, _max_total: int) -> void:
	_update_fragments()


func _on_total_changed(_id: StringName, _max_total: int) -> void:
	_update_fragments()


func _update_fragments() -> void:
	_fragments_label.text = tr("HUD_FRAGMENTS") % [GameSession.get_collected(FRAGMENT_ID), GameSession.get_total(FRAGMENT_ID)]


func _on_spell_learned(definition: Resource) -> void:
	if definition == null:
		_spell_label.text = tr("HUD_SPELL_NONE")
		_cooldown_bar.visible = false
		_crosshair.visible = false
	else:
		_spell_label.text = tr("HUD_SPELL") % tr(definition.display_name)
		_cooldown_bar.visible = true
		_crosshair.visible = true


func _on_focus_changed(interactable: Interactable) -> void:
	_focused = interactable
	if interactable == null:
		_prompt_label.visible = false
	else:
		_prompt_label.text = tr("HUD_PROMPT") % tr(interactable.prompt_text)
		_prompt_label.visible = true


func show_notification(text: String, duration: float = 3.0) -> void:
	_notification_label.text = text
	_notification_label.visible = true
	_notification_timer = duration


func _on_status_changed(status: int, message: String) -> void:
	_status = status
	_status_message = message
	match status:
		NetworkManager.Status.ONLINE:
			_status_label.text = tr("HUD_STATUS_ONLINE") % GameSession.display_name
		NetworkManager.Status.CONNECTING:
			_status_label.text = message if not message.is_empty() else tr("HUD_STATUS_CONNECTING")
		NetworkManager.Status.ERROR:
			_status_label.text = tr("HUD_STATUS_OFFLINE_REASON") % message
		_:
			_status_label.text = tr("HUD_STATUS_OFFLINE")


## Re-render the code-formatted labels when the language changes at runtime.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_fragments()
		_on_spell_learned(_caster.equipped_spell if _caster != null else null)
		if is_instance_valid(_focused):
			_on_focus_changed(_focused)
		_on_status_changed(_status, _status_message)
