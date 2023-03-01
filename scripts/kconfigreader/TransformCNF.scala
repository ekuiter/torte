package de.fosd.typechef.kconfig

import java.io._
import scala.collection.mutable.ListBuffer

import de.fosd.typechef.featureexpr.sat.{SATFeatureExpr}
import de.fosd.typechef.featureexpr._

object TransformCNF extends App {
    if (args.length != 1) {
        println("wrong usage");
        sys.exit(1)
    }
    val file :: tail = args.toList
    val parser = new FeatureExprParser()
    val reader = new BufferedReader(new FileReader(file + ".model"))
    var line = reader.readLine()
    var constraints = new ListBuffer[FeatureExpr]()
    while (line != null) {
        if (line.indexOf("#") == -1) {
            constraints += parser.parse(line)
        }
        line = reader.readLine()
    }
    new DimacsWriter().writeAsDimacs2(
        constraints.toList.map(_.asInstanceOf[SATFeatureExpr]),
        new File(file + ".dimacs"))
}