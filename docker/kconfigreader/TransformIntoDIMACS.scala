package de.fosd.typechef.kconfig

import java.io._
import scala.collection.mutable.ListBuffer

import de.fosd.typechef.featureexpr.sat.{SATFeatureExpr}
import de.fosd.typechef.featureexpr._

object TransformIntoDIMACS extends App {
    if (args.length != 2) {
        println("wrong usage");
        sys.exit(1)
    }
    val input :: tail = args.toList
    val output :: tail2 = tail.toList
    val parser = new FeatureExprParser()
    val reader = new BufferedReader(new FileReader(input))
    var line = reader.readLine()
    var constraints = new ListBuffer[FeatureExpr]()
    while (line != null) {
        if (line.indexOf("#") == -1) {
            try {
                constraints += parser.parse(line)
            } catch {
                case _: Throwable => System.err.println("could not parse constraint " + line.substring(0, 100))
            }
        }
        line = reader.readLine()
    }
    new DimacsWriter().writeAsDimacs2(
        constraints.toList.map(_.asInstanceOf[SATFeatureExpr]),
        new File(output))
}