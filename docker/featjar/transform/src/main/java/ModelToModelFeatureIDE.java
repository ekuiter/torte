import de.featjar.base.cli.Commands;
import de.ovgu.featureide.fm.core.io.manager.FileHandler;

import java.nio.file.Path;
import java.time.Duration;

public class ModelToModelFeatureIDE implements ITransformation {
    public void transform(Path inputPath, Path outputPath, Duration timeout) {
        Commands.runInThread(() -> {
            FileHandler.save(
                    outputPath,
                    ITransformation.loadModelFileWithFeatureIDE(inputPath),
                    new KConfigReaderFormat());
        }, timeout);
    }
}
