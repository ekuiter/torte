import de.ovgu.featureide.fm.core.base.*;
import de.ovgu.featureide.fm.core.editing.NodeCreator;
import de.ovgu.featureide.fm.core.io.AFeatureModelFormat;
import de.ovgu.featureide.fm.core.io.ProblemList;
import org.prop4j.*;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Format for reading KConfigReader .model files.
 * Alternatively, we could use FeatureIDE's {@link de.ovgu.featureide.fm.core.io.propositionalModel.MODELFormat}.
 * However, that format does not read non-Boolean constraints correctly and writes only CNFs.
 */
public class KConfigReaderFormat extends AFeatureModelFormat {
	private static Pattern equivalencePattern = Pattern.compile("def\\(([^()]*?)==CONFIG_(.*?)\\)");

	private static class KConfigNodeReader extends NodeReader {
		KConfigNodeReader() {
			try {
				Field field = NodeReader.class.getDeclaredField("symbols");
				field.setAccessible(true);
				field.set(this, new String[] { "==", "=>", "|", "&", "!" });
			} catch (NoSuchFieldException | IllegalAccessException e) {
				e.printStackTrace();
			}
		}
	}

	private static class KConfigNodeWriter extends NodeWriter {
		KConfigNodeWriter(Node root) {
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

	private static String fixNonBooleanConstraints(String l) {
		Matcher matcher = equivalencePattern.matcher(l);
		l = matcher.replaceAll(matchResult -> String.format("(%s<eq>%s)", matchResult.group(1), matchResult.group(2)));
		return l.replace("=", "_")
				.replace("<eq>", "==")
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

		final NodeReader nodeReader = new KConfigNodeReader();
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
						new KConfigNodeWriter(node).nodeToString().replace(" ", ""))).append("\n");
			}
			return sb.toString();
		} catch (NoSuchMethodException | InvocationTargetException | IllegalAccessException e) {
			e.printStackTrace();
		}
		return null;
	}

	private void addNodeToFeatureModel(IFeatureModel featureModel, Node node, Collection<String> variables) {
		final IFeature rootFeature = factory.createFeature(featureModel, "Root");
		FeatureUtils.addFeature(featureModel, rootFeature);
		featureModel.getStructure().setRoot(rootFeature.getStructure());

		// Add a feature for each variable.
		for (final String variable : variables) {
			final IFeature feature = factory.createFeature(featureModel, variable);
			FeatureUtils.addFeature(featureModel, feature);
			rootFeature.getStructure().addChild(feature.getStructure());
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
		return KConfigReaderFormat.class.getCanonicalName();
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
		return "KConfigReader .model";
	}

}
