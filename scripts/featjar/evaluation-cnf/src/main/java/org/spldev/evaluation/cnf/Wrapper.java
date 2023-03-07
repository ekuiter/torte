package org.spldev.evaluation.cnf;

import java.io.IOException;
import java.nio.file.*;
import java.util.*;

import org.spldev.evaluation.process.*;

public class Wrapper extends Algorithm<List<String>> {
	final Transformation transformation;

	public Wrapper(Transformation transformation) {
		this.transformation = transformation;
	}

	@Override
	protected void addCommandElements() {
		Path tempPath = Paths.get(transformation.parameters.tempPath).resolve("params.dat");
		transformation.write(tempPath);
		addCommandElement("java");
		addCommandElement("-da");
		addCommandElement("-Xmx12g");
		addCommandElement("-cp");
		addCommandElement(System.getProperty("java.class.path"));
		addCommandElement(Runner.class.getCanonicalName());
		addCommandElement(tempPath.toString());
	}

	@Override
	public void postProcess() {
	}

	@Override
	public List<String> parseResults() {
		return null;
	}

	@Override
	public String getName() {
		return "Evaluation-CNF";
	}

	@Override
	public String getParameterSettings() {
		return transformation.toString();
	}
}
