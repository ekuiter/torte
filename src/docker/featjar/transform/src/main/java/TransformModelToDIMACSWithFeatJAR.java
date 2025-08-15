import de.featjar.base.cli.Commands;
import de.featjar.base.io.IO;
import de.featjar.formula.io.dimacs.DIMACSFormulaFormat;
import de.featjar.formula.transformer.ComputeCNFFormula;
import de.featjar.formula.transformer.ComputeNNFFormula;

import java.nio.file.Path;
import java.time.Duration;

import static de.featjar.base.computation.Computations.async;

public class TransformModelToDIMACSWithFeatJAR implements ITransformation {
    public void transform(Path inputPath, Path outputPath, Duration timeout) {
        Commands.runInThread(() -> {
            IO.save(async(ITransformation.loadModelFileWithFeatJAR(inputPath))
                    .map(ComputeNNFFormula::new)
                    .map(ComputeCNFFormula::new)
                    .get()
                    .get(), outputPath, new DIMACSFormulaFormat());
        }, timeout);
    }
}