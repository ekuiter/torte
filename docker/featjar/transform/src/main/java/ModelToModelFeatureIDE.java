import de.featjar.base.cli.Commands;
import de.ovgu.featureide.fm.core.io.manager.FileHandler;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

public class ModelToModelFeatureIDE implements ITransformation {


    public void transform(Path inputPath, Path outputPath, Duration timeout) {
        Commands.runInThread(() -> {
            try {

                String content = Files.readString(inputPath);
                if (content.contains("definedEx(")) {
                    FileHandler.save(
                            outputPath,
                            ITransformation.loadModelFileWithFeatureIDE(inputPath),
                            new ConFigFixFormat() 
                    );
                } else {
                    FileHandler.save(
                            outputPath,
                            ITransformation.loadModelFileWithFeatureIDE(inputPath),
                            new KConfigReaderFormat() 
                    );
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }, timeout);
    }
}

