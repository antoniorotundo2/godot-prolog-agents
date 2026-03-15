package app

import io.circe.{Decoder, Encoder}
import io.circe.generic.semiauto.*

final case class WsRequest(agent: String, percepts: List[String], theory: Option[String])
final case class WsResponse(agent: String, action: String, energy: Int)
final case class WsError(error: String)

object Protocol:
  given Decoder[WsRequest] = deriveDecoder[WsRequest]
  given Encoder[WsResponse] = deriveEncoder[WsResponse]
  given Encoder[WsError] = deriveEncoder[WsError]

