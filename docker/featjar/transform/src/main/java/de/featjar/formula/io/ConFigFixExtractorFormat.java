/*
 * Copyright (C) 2023 Sebastian Krieter, Elias Kuiter
 *
 * This file is part of FeatJAR-formula.
 *
 * formula is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3.0 of the License,
 * or (at your option) any later version.
 *
 * formula is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with formula. If not, see <https://www.gnu.org/licenses/>.
 *
 * See <https://github.com/FeatureIDE/FeatJAR-formula> for further information.
 */
package de.featjar.formula.io;

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
 * Parses feature-model formula files created by ConfigFix.
 * @author Rami Alfish
 */
public class ConFigFixExtractorFormat implements IFormat<IExpression> {

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
                        .map(l -> l.replace("=", "_"))
                        .map(l -> l.replace(":", "_"))
                        .map(l -> l.replace(".", "_"))
                        .map(l -> l.replace(",", "_"))
                        .map(l -> l.replace("/", "_"))
                        .map(l -> l.replace("\\", "_"))
                        .map(l -> l.replace("-", "_"))
                        .map(l -> l.replace("&&", "&"))
                        .map(l -> l.replace("||", "|"))
                        .map(l -> l.replaceAll("definedEx\\((\\w+)\\)", "$1"))
                        .map(expressionParser::parse)
                        .peek(r -> problems.addAll(r.getProblems()))
                        .filter(Result::isPresent)
                        .map(expressionResult -> (IFormula) expressionResult.get())
                        .collect(Collectors.toList())),
                problems);
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
        return "ConFigFixExtractor";
    }
}
