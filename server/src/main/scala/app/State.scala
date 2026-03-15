package app

final case class AgentState(
  energy: Int,
  lastAction: String,
  lastPercepts: List[String],
  lastDecisionAtMs: Long
)

final case class ServerState(
  agents: Map[String, AgentState],
  theories: Map[String, String]
)

object ServerState:
  def empty: ServerState =
    ServerState(Map.empty, Map.empty)

object AgentState:
  private val MinEnergy = 0
  private val MaxEnergy = 100

  def initial: AgentState =
    AgentState(
      energy = 100,
      lastAction = "none",
      lastPercepts = Nil,
      lastDecisionAtMs = 0L
    )

  private def deltaFor(action: String): Int =
    action match
      case "move_forward" => -5
      case "turn_left"    => -2
      case "turn_right"   => -2
      case "go_straight"  => -2
      case "u_turn"       => -3
      case "turn_random"  => -2
      case "drive"        => -2
      case "accelerate"   => -3
      case "cruise"       => -1
      case "slow"         => -1
      case "slow_down"    => -1
      case "stop"         => 0
      case "brake"        => 0
      case "wait"         => 1
      case "idle"         => -1
      case "attack"       => -8
      case "flee"         => -6
      case "rest"         => 10
      case "celebrate"    => 5
      case "wander"       => -3
      case _              => -1

  def next(
    state: AgentState,
    action: String,
    percepts: List[String],
    decidedAtMs: Long
  ): AgentState =
    val updated = state.energy + deltaFor(action)
    val clamped = math.max(MinEnergy, math.min(MaxEnergy, updated))
    state.copy(
      energy = clamped,
      lastAction = action,
      lastPercepts = percepts,
      lastDecisionAtMs = decidedAtMs
    )

  def touch(
    state: AgentState,
    percepts: List[String],
    touchedAtMs: Long
  ): AgentState =
    state.copy(
      lastPercepts = percepts,
      lastDecisionAtMs = touchedAtMs
    )

  def canReuseDecision(
    state: AgentState,
    percepts: List[String],
    nowMs: Long,
    windowMs: Long
  ): Boolean =
    state.lastAction != "none" &&
    state.lastPercepts == percepts &&
    (nowMs - state.lastDecisionAtMs) <= windowMs

