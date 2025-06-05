import de.featjar.base.FeatJAR;
import de.featjar.base.extension.IExtension;
import de.featjar.base.io.IO;
import de.featjar.formula.io.FormulaFormats;
import de.featjar.formula.structure.formula.IFormula;
import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.base.impl.FMFormatManager;
import de.ovgu.featureide.fm.core.init.FMCoreLibrary;
import de.ovgu.featureide.fm.core.init.LibraryManager;
import de.ovgu.featureide.fm.core.io.manager.FeatureModelManager;
import de.featjar.formula.io.ConfigFixFormat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Optional;

public interface ITransformation extends IExtension {
    void transform(Path inputPath, Path outputPath, Duration timeout) throws Exception;

    static IFormula loadModelFileWithFeatJAR(Path inputPath) {
        try {
            String content = Files.readString(inputPath);
            // to do ConfigFix: can we do this a bit more elegantly? maybe actually introduce a new file extension for ConfigFix, which then gets transformed into standard model format?
            if (content.contains("definedEx(")) {
                return (IFormula) IO.load(inputPath, new ConfigFixFormat())
                            .orElseThrow(p -> new RuntimeException("failed to load feature model at " + inputPath));
            } else {
                return (IFormula) IO.load(inputPath,  FeatJAR.extensionPoint(FormulaFormats.class))
                            .orElseThrow(p -> new RuntimeException("failed to load feature model at " + inputPath));
            }
        } catch (IOException e) {
            throw new RuntimeException("Failed to read file: " + inputPath, e);
        }
    }

    static IFeatureModel loadModelFileWithFeatureIDE(Path inputPath) throws IOException {
        LibraryManager.registerLibrary(FMCoreLibrary.getInstance());

        String content = Files.readString(inputPath);
        if (content.contains("definedEx(")) {
            FMFormatManager.getInstance().addExtension(new ConfigFixFormat());
        } else {
            FMFormatManager.getInstance().addExtension(new KConfigReaderFormat());
        }

        IFeatureModel featureModel = FeatureModelManager.load(inputPath);
        if (featureModel == null) {
            throw new RuntimeException("Failed to load feature model at " + inputPath);
        }
        return featureModel;
    }
}

