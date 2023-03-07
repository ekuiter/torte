package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.base.impl.FMFormatManager;
import de.ovgu.featureide.fm.core.init.FMCoreLibrary;
import de.ovgu.featureide.fm.core.init.LibraryManager;
import org.spldev.util.extension.ExtensionLoader;

import java.nio.file.Paths;
import java.util.Objects;

public class Runner {
	public static void main(String[] args) throws Exception {
		if (args.length != 1) {
			throw new RuntimeException("invalid usage");
		}
		ExtensionLoader.load();
		LibraryManager.registerLibrary(FMCoreLibrary.getInstance());
		FMFormatManager.getInstance().addExtension(new KConfigReaderFormat());
		Transformation transformation = Transformation.read(Paths.get(args[0]));
		Objects.requireNonNull(transformation);
		System.out.println(transformation.parameters);
		transformation.run();
	}
}
