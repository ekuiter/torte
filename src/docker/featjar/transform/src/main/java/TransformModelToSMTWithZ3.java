import de.featjar.base.FeatJAR;
import de.featjar.base.cli.Commands;
import de.featjar.base.io.IO;
import de.featjar.formula.analysis.javasmt.solver.FormulaToJavaSMT;
import de.featjar.formula.io.FormulaFormats;
import de.featjar.formula.structure.formula.IFormula;
import org.sosy_lab.common.ShutdownManager;
import org.sosy_lab.common.configuration.Configuration;
import org.sosy_lab.common.configuration.InvalidConfigurationException;
import org.sosy_lab.common.log.BasicLogManager;
import org.sosy_lab.java_smt.SolverContextFactory;
import org.sosy_lab.java_smt.api.BooleanFormula;
import org.sosy_lab.java_smt.api.FormulaManager;
import org.sosy_lab.java_smt.api.SolverContext;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.io.IOException;

public class TransformModelToSMTWithZ3 implements ITransformation {
    public void transform(Path inputPath, Path outputPath, Duration timeout) {
        Commands.runInThread(() -> {
            // to do ConfigFix: can we do this a bit more elegantly and revert the merge commit?
            try {
                IFormula formula;
                String content = Files.readString(inputPath);
                if (content.contains("definedEx(")) {
                    formula = (IFormula) IO.load(inputPath, new ConfigFixFormatFeatJAR())
                            .orElseThrow(p -> new RuntimeException("failed to load feature model at " + inputPath));
                            Files.write(outputPath, formulaToSMTString(formula).getBytes());
                } else {
                    formula = (IFormula) IO.load(inputPath,  FeatJAR.extensionPoint(FormulaFormats.class))
                            .orElseThrow(p -> new RuntimeException("failed to load feature model at " + inputPath));
                        Files.write(outputPath, formulaToSMTString(formula).getBytes());
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }, timeout);


//        Files.write(Paths.get(parameters.tempPath).resolve(
//                        String.format("%s_%d.stats",
//                                parameters.system.replaceAll("[/]", "_"),
//                                parameters.iteration)),
//                (variableMap.size() + " " + Trees.traverse(formula, new LiteralsCounter()).get()).getBytes());
    }

    private static String formulaToSMTString(IFormula formula) throws InvalidConfigurationException {
        Configuration config = Configuration.defaultConfiguration();
        SolverContext context = SolverContextFactory.createSolverContext(
                config,
                BasicLogManager.create(config),
                ShutdownManager.create().getNotifier(),
                SolverContextFactory.Solvers.Z3);
        FormulaManager formulaManager = context.getFormulaManager();
        BooleanFormula smtFormula = new FormulaToJavaSMT(context).nodeToFormula(formula);
        return formulaManager.dumpFormula(smtFormula).toString();
    }

//    private static class LiteralsCounter implements TreeVisitor<Integer, Tree<?>> {
//
//        private int literals = 0;
//
//        @Override
//        public void reset() {
//            literals = 0;
//        }
//
//        @Override
//        public VisitorResult firstVisit(List<Tree<?>> path) {
//            if (TreeVisitor.getCurrentNode(path) instanceof Atomic)
//                literals++;
//            return VisitorResult.Continue;
//        }
//
//        @Override
//        public Integer getResult() {
//            return literals;
//        }
//    }
}