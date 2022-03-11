package org.spldev.evaluation.cnf;

import org.spldev.evaluation.Evaluator;
import org.spldev.evaluation.process.ProcessRunner;
import org.spldev.evaluation.util.ModelReader;
import org.spldev.formula.expression.Formula;
import org.spldev.formula.expression.io.FormulaFormatManager;

import java.util.Arrays;

public class CNFExtractor extends Evaluator {
	protected ProcessRunner processRunner;

	@Override
	public String getName() {
		return "extract-cnf";
	}

	@Override
	public String getDescription() {
		return "Extract CNF formulas from feature models";
	}

	@Override
	public void evaluate() {
		tabFormatter.setTabLevel(0);
		final ModelReader<Formula> fmReader = new ModelReader<>();
		fmReader.setPathToFiles(config.modelPath);
		fmReader.setFormatSupplier(FormulaFormatManager.getInstance());
		processRunner = new ProcessRunner();
		processRunner.setTimeout(config.timeout.getValue() * 2);
		for (systemIteration = 0; systemIteration < config.systemIterations.getValue(); systemIteration++) {
			for (systemIndex = 0; systemIndex < config.systemNames.size(); systemIndex++) {
				String modelPath = config.systemNames.get(systemIndex);
				String system = modelPath
					.replace(".kconfigreader.model", "")
					.replace(".xml", "");
				Parameters parameters = new Parameters(
					system, config.modelPath.toString(),
					modelPath, systemIteration, config.tempPath.toString(), config.timeout.getValue());
				tabFormatter.setTabLevel(0);
				logSystem();
				tabFormatter.setTabLevel(1);
				Arrays.stream(Transformation.transformations).forEach(transformation ->
						evaluateForParameters(parameters, transformation));
			}
		}
	}

	private void evaluateForParameters(Parameters parameters, Transformation transformation) {
		tabFormatter.setTabLevel(2);
		transformation.setParameters(parameters);
		Wrapper wrapper = new Wrapper(transformation);
		tabFormatter.incTabLevel();
		processRunner.run(wrapper);
		tabFormatter.decTabLevel();
	}
}
