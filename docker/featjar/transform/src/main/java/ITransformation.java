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

import java.nio.file.Path;
import java.time.Duration;

public interface ITransformation extends IExtension {
    void transform(Path inputPath, Path outputPath, Duration timeout) throws Exception;

    static IFormula loadModelFileWithFeatJAR(Path inputPath) {
        return IO.load(inputPath, FeatJAR.extensionPoint(FormulaFormats.class))
                .orElseThrow(p -> new RuntimeException("failed to load feature model at " + inputPath));
    }

	static IFeatureModel loadModelFileWithFeatureIDE(Path inputPath) {
	    LibraryManager.registerLibrary(FMCoreLibrary.getInstance());
	    FMFormatManager.getInstance().addExtension(new KConfigReaderFormat());
	    FMFormatManager.getInstance().addExtension(new ConFigFixFormat());

	    final IFeatureModel featureModel = FeatureModelManager.load(inputPath);
	    if (featureModel == null) {
		throw new RuntimeException("Failed to load feature model at " + inputPath);
	    }
	    return featureModel;
	}

}
