package app

import alice.tuprolog.{Prolog, Theory}

import scala.io.Source
import scala.util.control.NonFatal

trait PrologService:
  def decideAction(
    percepts: List[String],
    theoryOverride: Option[String]
  ): Either[AppError, String]

object LivePrologService extends PrologService:
  private lazy val defaultTheoryText: Option[String] =
    try
      val src = Source.fromResource("logic.pl")
      try Some(src.mkString)
      finally src.close()
    catch
      case NonFatal(_) => None

  private def normalizeAtom(value: String): String =
    if value.startsWith("'") && value.endsWith("'") && value.length >= 2 then
      value.substring(1, value.length - 1)
    else value

  private def toPrologList(items: List[String]): String =
    val escaped = items.map { p =>
      val safe = p.replace("\\", "\\\\").replace("\"", "\\\"")
      "\"" + safe + "\""
    }
    escaped.mkString("[", ",", "]")

  override def decideAction(
    percepts: List[String],
    theoryOverride: Option[String]
  ): Either[AppError, String] =
    val theoryTextOpt =
      theoryOverride.filter(_.trim.nonEmpty).orElse(defaultTheoryText)

    theoryTextOpt match
      case None =>
        Left(AppError.MissingTheory)
      case Some(theoryText) =>
        try
          val engine = new Prolog()
          engine.setTheory(new Theory(theoryText))
          val goal = s"decide_action(${toPrologList(percepts)}, Action)."
          val solution = engine.solve(goal)
          if solution.isSuccess then
            Right(normalizeAtom(solution.getTerm("Action").toString))
          else Left(AppError.NoSolution)
        catch
          case NonFatal(ex) => Left(AppError.PrologFailure(ex.getMessage))

