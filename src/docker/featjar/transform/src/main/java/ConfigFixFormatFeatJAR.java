import de.featjar.base.data.Problem;
import de.featjar.base.data.Result;
import de.featjar.base.io.format.IFormat;
import de.featjar.base.io.input.AInputMapper;
import de.featjar.formula.io.textual.ExpressionParser;
import de.featjar.formula.io.textual.PropositionalModelSymbols;
import de.featjar.formula.structure.IExpression;
import de.featjar.formula.structure.formula.IFormula;
import de.featjar.formula.structure.formula.connective.And;

import java.util.ArrayList;
import java.util.stream.Collectors;

/**
 * Parses feature-model formula files with definedEx(...) syntax (e.g. from ConfigFix).
 * Cleans and normalizes input without corrupting variable names.
 * 
 * @author Rami
 */
public class ConfigFixFormatFeatJAR implements IFormat<IExpression> {

    @Override
    public Result<IExpression> parse(AInputMapper inputMapper) {
        final ArrayList<Problem> problems = new ArrayList<>();
        final ExpressionParser expressionParser = new ExpressionParser();
        expressionParser.setSymbols(PropositionalModelSymbols.INSTANCE);

        return Result.of(
            new And(inputMapper
                .get()
                .getLineStream()
                .map(String::trim)
                .filter(l -> !l.isEmpty())
                .filter(l -> !l.startsWith("#"))
                .map(this::normalizeLine)
                .map(expressionParser::parse)
                .peek(r -> problems.addAll(r.getProblems()))
                .filter(Result::isPresent)
                .map(expressionResult -> (IFormula) expressionResult.get())
                .collect(Collectors.toList())),
            problems);
    }

    /**
     * Cleans a line by replacing only critical syntax characters, preserving variable names.
     */
    private String normalizeLine(String line) {
        return line
            .replace("&&", "&")
            .replace("||", "|")
            // Remove problematic characters only *outside* variable names
            .replaceAll("definedEx\\(([\\w\\-/\\.]+)\\)", "$1")
            // Optionally normalize remaining bad characters (if any)
            .replaceAll("[=,:\\\\]", "_");
    }

    @Override
    public boolean supportsParse() {
        return true;
    }

    @Override
    public boolean supportsSerialize() {
        return false;
    }

    @Override
    public String getFileExtension() {
        return "model";
    }

    @Override
    public String getName() {
        return "ConFigFix";
    }
}

