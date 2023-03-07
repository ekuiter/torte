package org.spldev.evaluation.cnf;

import java.io.Serializable;

public class Parameters implements Serializable {
	private static final long serialVersionUID = 1L;
	public String system;
	public String rootPath;
	public String modelPath;
	public int iteration;
	public String tempPath;
	public long timeout;
	public Transformation transformation;

	public Parameters(String system, String rootPath, String modelPath, int iteration, String tempPath,
		long timeout) {
		this.system = system;
		this.rootPath = rootPath;
		this.modelPath = modelPath;
		this.iteration = iteration;
		this.tempPath = tempPath;
		this.timeout = timeout;
	}

	@Override
	public String toString() {
		return String.format(
			"Parameters{rootPath='%s', modelPath='%s', iteration=%d, tempPath='%s', timeout=%d, transformation=%s}",
			rootPath, modelPath, iteration, tempPath, timeout, transformation);
	}
}
