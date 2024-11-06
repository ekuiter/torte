import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.base.IFeature;
import de.ovgu.featureide.fm.core.base.impl.FeatureUtils;
import de.ovgu.featureide.fm.core.io.AFeatureModelFormat;
import de.ovgu.featureide.fm.core.io.ProblemList;
import org.prop4j.*;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.*;
import java.util.regex.Pattern;
import java.util.regex.Matcher;
import java.util.stream.Collectors;


public class ConfigfixFormatter extends AFeatureModelFormat {
    // Pattern for parsing specific configfix expressions, adjust as needed.
    private static final Pattern customPattern = Pattern.compile("definedEx\\(([^()]*?)\\)");

   
    private static class ConfigfixNodeReader extends NodeReader {
        ConfigfixNodeReader() {
            try {
                Field field = NodeReader.class.getDeclaredField("symbols");
                field.setAccessible(true);
                field.set(this, new String[] { "==", "=>", "|", "&", "!" });
            } catch (NoSuchFieldException | IllegalAccessException e) {
                e.printStackTrace();
            }
        }
    }


    private static class ConfigfixNodeWriter extends NodeWriter {
        ConfigfixNodeWriter(Node root) {
            super(root);
            setEnforceBrackets(true);
            try {
                Field field = NodeWriter.class.getDeclaredField("symbols");
                field.setAccessible(true);
                field.set(this, new String[]{"!", "&", "|", "=>", "==", "<ERR>", "<ERR>", "<ERR>", "<ERR>"});
            } catch (NoSuchFieldException | IllegalAccessException e) {
                e.printStackTrace();
            }
        }

        @Override
        protected String variableToString(Object variable) {
            //Uses "def" instead of "definedEx" in the output format
            return "def(" + super.variableToString(variable) + ")";
        }
    }

    // Adjustments for handling specific configfix syntax, if necessary
    private static String adjustCustomExpressions(String line) {
        Matcher matcher = customPattern.matcher(line);
        return matcher.replaceAll(matchResult -> matchResult.group(1))
                      .replace("=", "_")
                      .replace(":", "_")
                      .replace(".", "_")
                      .replace(",", "_")
                      .replace("/", "_")
                      .replace("\\", "_")
                      .replace(" ", "_")
                      .replace("-", "_");
    }

	
	// ToDO (FilePath)
        public ProblemList readFromTxtFile(IFeatureModel featureModel, String filePath) throws IOException {
        setFactory(featureModel); 

        final NodeReader nodeReader = new ConfigfixNodeReader(); 


        List<Node> constraints = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(filePath))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (!line.isEmpty()) {
                    line = adjustCustomExpressions(line); an
                    line = line.replaceAll("definedEx\\((\\w+)\\)", "$1"); 
                    Node node = nodeReader.stringToNode(line); 
                    if (node != null) {
                        constraints.add(node);
                    }
                }
            }
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
                node = (Node) method.invoke(node);
                sb.append(adjustCustomExpressions(
                        new ConfigfixNodeWriter(node).nodeToString().replace(" ",   ""))).append("\n");
            }
            return sb.toString();
        } catch (NoSuchMethodException | InvocationTargetException | IllegalAccessException e) {
            e.printStackTrace();
        }
        return null;
    }

    private void addNodesToFeatureModel(IFeatureModel featureModel, Node node, Collection<String> variables) {
        final IFeature rootFeature = factory.createFeature(featureModel, "Root");
        FeatureUtils.addFeature(featureModel, rootFeature);
        featureModel.getStructure().setRoot(rootFeature.getStructure());

        for (final String variable : variables) {
            final IFeature feature = factory.createFeature(featureModel, variable);
            FeatureUtils.addFeature(featureModel, feature);
            rootFeature.getStructure().addChild(feature.getStructure());
        }

        List<Node> clauses = node instanceof And ? Arrays.asList(node.getChildren())
                                                 : Collections.singletonList(node);
        for (final Node clause : clauses) {
            FeatureUtils.addConstraint(featureModel, factory.createConstraint(featureModel, clause));
        }
    }

    @Override
    public String getSuffix() {
        return "configfix";
    }

    @Override
    public ConfigfixFormatter getInstance() {
        return this;
    }

    @Override
    public String getId() {
        return ConfigfixFormatter.class.getCanonicalName();
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
        return "Configfix Formatter";
    }
}
