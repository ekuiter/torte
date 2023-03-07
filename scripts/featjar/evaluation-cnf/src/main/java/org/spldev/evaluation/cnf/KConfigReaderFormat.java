package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.PluginID;
import de.ovgu.featureide.fm.core.base.*;
import de.ovgu.featureide.fm.core.editing.NodeCreator;
import de.ovgu.featureide.fm.core.io.AFeatureModelFormat;
import de.ovgu.featureide.fm.core.io.ProblemList;
import org.prop4j.*;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Alternatively, we could use FeatureIDE's MODELFormat.
 * But, MODELFormat does not read non-Boolean constraints correctly and writes only CNFs.
 */
public class KConfigReaderFormat extends AFeatureModelFormat {
	static class KconfigNodeReader extends NodeReader {
		KconfigNodeReader() {
			try {
				Field field = NodeReader.class.getDeclaredField("symbols");
				field.setAccessible(true);
				field.set(this, new String[] { "==", "=>", "|", "&", "!" });
			} catch (NoSuchFieldException | IllegalAccessException e) {
				e.printStackTrace();
			}
		}
	}

	static class KconfigNodeWriter extends NodeWriter {
		KconfigNodeWriter(Node root) {
			super(root);
			setEnforceBrackets(true);
			try {
				Field field = NodeWriter.class.getDeclaredField("symbols");
				field.setAccessible(true);
				// nonstandard operators are not supported
				field.set(this, new String[]{"!", "&", "|", "=>", "==", "<ERR>", "<ERR>", "<ERR>", "<ERR>"});
			} catch (NoSuchFieldException | IllegalAccessException e) {
				e.printStackTrace();
			}
		}

		@Override
		protected String variableToString(Object variable) {
			return "def(" + super.variableToString(variable) + ")";
		}
	}

	public static final String ID = PluginID.PLUGIN_ID + ".format.fm." + KConfigReaderFormat.class.getSimpleName();

	private static String fixNonBooleanConstraints(String l) {
		return l.replace("=", "_")
				.replace(":", "_")
				.replace(".", "_")
				.replace(",", "_")
				.replace("/", "_")
				.replace("\\", "_")
				.replace(" ", "_")
				.replace("-", "_");
	}

	@Override
	public ProblemList read(IFeatureModel featureModel, CharSequence source) {
		setFactory(featureModel);

		final NodeReader nodeReader = new KconfigNodeReader();
		List<Node> constraints = source.toString().lines() //
			.map(String::trim) //
			.filter(l -> !l.isEmpty()) //
			.filter(l -> !l.startsWith("#")) //
			.map(KConfigReaderFormat::fixNonBooleanConstraints)
			.map(l -> l.replaceAll("def\\((\\w+)\\)", "$1"))
			.map(nodeReader::stringToNode) //
			.filter(Objects::nonNull) // ignore non-Boolean constraints
			.collect(Collectors.toList());

		featureModel.reset();
		And andNode = new And(constraints);
		addNodeToFeatureModel(featureModel, andNode, andNode.getUniqueContainedFeatures());

		return new ProblemList();
	}

	@Override
	public String write(IFeatureModel featureModel) {
		try {
			final IFeature root = FeatureUtils.getRoot(featureModel);
			final List<Node> nodes = new LinkedList<>();
			if (root != null) {
				nodes.add(new Literal(NodeCreator.getVariable(root.getName(), featureModel)));
				Method method = NodeCreator.class.getDeclaredMethod("createNodes", Collection.class, IFeature.class, IFeatureModel.class, boolean.class, Map.class);
				method.setAccessible(true);
				method.invoke(NodeCreator.class, nodes, root, featureModel, true, Collections.emptyMap());
			}
			for (final IConstraint constraint : new ArrayList<>(featureModel.getConstraints())) {
				nodes.add(constraint.getNode().clone());
			}

			StringBuilder sb = new StringBuilder();
			Method method = Node.class.getDeclaredMethod("eliminateNonCNFOperators");
			method.setAccessible(true);
			for (Node node : nodes) {
				// replace nonstandard operators (usually, only AtMost for alternatives) with hardcoded CNF patterns
				node = (Node) method.invoke(node);
				// append constraint to the built .model file
				sb.append(fixNonBooleanConstraints(
						new KconfigNodeWriter(node).nodeToString().replace(" ", ""))).append("\n");
			}
			return sb.toString();
		} catch (NoSuchMethodException | InvocationTargetException | IllegalAccessException e) {
			e.printStackTrace();
		}
		return null;
	}

	/**
	 * Adds the given propositional node to the given feature model. The current
	 * implementation is naive in that it does not attempt to interpret any
	 * constraint as {@link IFeatureStructure structure}.
	 *
	 * @param featureModel feature model to edit
	 * @param node         propositional node to add
	 * @param variables    the variables of the propositional node
	 */
	private void addNodeToFeatureModel(IFeatureModel featureModel, Node node, Collection<String> variables) {
		// Add a feature for each variable.
		for (final String variable : variables) {
			final IFeature feature = factory.createFeature(featureModel, variable.toString());
			FeatureUtils.addFeature(featureModel, feature);
		}

		// Add a constraint for each conjunctive clause.
		final List<Node> clauses = node instanceof And ? Arrays.asList(node.getChildren())
			: Collections.singletonList(node);
		for (final Node clause : clauses) {
			FeatureUtils.addConstraint(featureModel, factory.createConstraint(featureModel, clause));
		}
	}

	@Override
	public String getSuffix() {
		return "model";
	}

	@Override
	public KConfigReaderFormat getInstance() {
		return this;
	}

	@Override
	public String getId() {
		return ID;
	}

	@Override
	public boolean supportsRead() {
		return true;
	}

	@Override
	public boolean supportsWrite() {
		return true;
	}

	@Override
	public String getName() {
		return "kconfigreader";
	}

}
