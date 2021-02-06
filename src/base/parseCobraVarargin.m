function [funParams, cobraParams, solverVarargin] = parseCobraVarargin(varArgIn, optArgin, defaultValues, validator, problemTypes, keyForSolverParams, emptyForDefault)
% Parse varargin for a COBRA function to obtain function inputs and
% cobra-problem-specific parameters. Used to handle inputs for functions
% supporting all of (i) direct argument inputs, (ii) name-value inputs, and
% (iii) parameter structure inputss
%
% USAGE:
%    [funParams, cobraParams, solverVaragin] = parseCobraVarargin(optArgin, defaultValues, validator, problemTypes, keyForSolverParams, emptyForDefault)
%
% INPUTS:
%    varArgIn:          cell array of additional inputs for the function (= varargin in that function)
%    optArgin:          cell array of strings for the optional arguments of a function 
%    defaultValues:     cell array of default values corresponding to optArgin
%    validator:         cell array of function handles for validating the inputs corresponding to optArgin
%                         Will return error if the inputs do not return true from the validator
%
% OPTIONAL INPUTS:
%    problemTypes:       cell array of cobra supported optimization problems needed to solve in the function
%                        (default {'LP', 'MILP', 'QP', 'MIQP'})
%    keyForSolverParams: the keyword for solver-specific parameter structure in `optArgin` if solver-specific parameter structure
%                        is an explicit optional input argument in optArgin (which is NOT encouraged when writing cobra functions
%                        because the solver-specific parameter structure as a convention among cobra functions can be inputted 
%                        without keyword and is handled this way in this parsing process). 
%                        If this is the case, provide the keyword and it will be handled (default ''). Note that in this case
%                        the solver parameter structure will not be included in `funParams` but instead integrated in `solverVaragin`
%    emptyForDefault:      True to interpret empty inputs for positional arguments as using the default values (default false)
%
% OUTPUTS:
%    funParams:          cell array of optional argument inputs corresponding to optArgin.
%                         Can be assigned in the function easily by [argIn1, argIn2, ...] = deal(funParams{:})
%    cobraParams:        structure containing parsed cobra parameters for each problem type in `problemTypes`, 
%                        to be used within the cobra function being written.
%    solverVaragin:      structure containing parsed cobra-problem-specific addition inputs as a cell array for each problem type in `problemTypes`,
%                        with the first cell being the solver-specific parameter structure
%                        e.g., solverVarargin.LP contains the additional inputs for solveCobraLP, with solverVarargin.LP{1}
%                        being the solver-specific parameter structure, called as solveCobraLP(LPproblem, solverVarargin.LP{:})

if nargin < 5 || isempty(problemTypes)
    problemTypes = {'LP', 'MILP', 'QP', 'MIQP', 'NLP'};
elseif any(~ismember(problemTypes, {'LP', 'MILP', 'QP', 'MIQP', 'NLP'}))
    if ischar(problemTypes), problemTypes = {problemTypes}; end
    error('Input %s for `ProblemTypes` not supported. Only ''LP'', ''MILP'', ''QP'' and ''MIQP'' are supported', strjoin(problemTypes, ', '))
end
if nargin < 6 || isempty(keyForSolverParams)
    keyForSolverParams = '';
elseif ~ischar(keyForSolverParams)
    error('Input `keyForSolverParams` must be a string')
end
if nargin < 7
    emptyForDefault = false;
end

cobraOptions = getCobraSolverParamsOptionsForType(problemTypes);

pSpos = 1;
% parse the inputs accordingly.
paramValueInput = false;

% Check if we have parameter/value inputs.
        
% Handle the case where `keyForSolverParams` (solver-specific parameters) is an explicit function input argument
% (which is NOT encouraged when writing cobra functions because the solver-specific parameter
%  structure as a convention among cobra functions can be inputted as a structure without keyword )
%
% If this is the case, detect if it is supplied as a direct input or name-value argument:
% Order of `keyForSolverParams` in the optional input optArgin (0 if not in there):
PosSolverParams = 0; 
% find the position
idTmp = strcmp(optArgin, keyForSolverParams);
if any(idTmp)
    % remove the keyword from optArgin, defaultValues and validator. It will not
    % be in the output funParams, but integrated into solverVaragin instead
    optArgin = optArgin(~idTmp);
    defaultValues = defaultValues(~idTmp);
    validator = validator(~idTmp);
    
    if ~isempty(varArgIn)
        % check if `keyForSolverParams` is supplied as name-value input
        sPInVin = find(cellfun(@(x) ischar(x) && strncmpi(x, keyForSolverParams, length(x)), varArgIn));
        if ~isempty(sPInVin) && numel(sPInVin) ~= numel(varArgIn)
            % if the keyword is found (i.e., solver parameters inputted as name-value argument)
            % remove the keyword and put the structure at the end
            varArgIn = [varArgIn(1:(sPInVin - 1)), ...
                varArgIn((sPInVin + 2):end), varArgIn(sPInVin + 1)];
        else
            % keyword not found in varargin, could still be a direct input. Detect below
            PosSolverParams = find(idTmp);
        end
    end
end
for pSpos = 1:numel(varArgIn)
    if isstruct(varArgIn{pSpos})
        if pSpos == PosSolverParams && numel(varArgIn) > PosSolverParams
            % if PosSolverParams is non-zero and a solver-specific parameter structure is a direct input
            % Put it as the last argument, as if the standard way of inputting solver-specific parameter structure.
            % Then continue to see if the next input is a direct input.
            % If the structure is the last optional input, then no need to change.
            % But need to break with the paramValueInput flag on
            varArgIn = [varArgIn(1:(pSpos - 1)), varArgIn((pSpos + 1):end), varArgIn(pSpos)];
        elseif numel(validator) < pSpos || ~validator{pSpos}(varArgIn{pSpos})
            % it is a struct and does not pass the validator for the corresponding positional argument.
            % So yes, we do have additional inputs.
            paramValueInput = true;
            break;
        end
    end
    if ~isempty(varArgIn{pSpos}) && ischar(varArgIn{pSpos}) && ...  % ~validator{pSpos}(varArgIn{pSpos}) && ...
            (any(strncmpi(varArgIn{pSpos}, optArgin, length(varArgIn{pSpos}))) ...
            || any(ismember(varArgIn{pSpos}, cobraOptions)))
        % its a keyword (partial matching supported), so yes, we have paramValue input.
        paramValueInput = true;
        break
    end
end

parser = inputParser();
% parameters not matched to function input keywords
otherParams = struct();
knownSolverParamFields = {};
if ~paramValueInput
    % we only have values specific to this function. Parse the data.
    nArg = min(numel(varArgIn),numel(optArgin));
    optArgOrder = 1:numel(optArgin);
    if emptyForDefault
        argDefault = cellfun(@isempty, varArgIn(1:nArg));
        % re-order the positional arguments such that all non-empty inputs go first
        nArg = sum(~argDefault);
        optArgOrder = [columnVector(find(~argDefault)); columnVector(setdiff(1:numel(optArgin), find(~argDefault)))]';
    end
    for jArg = optArgOrder
        parser.addOptional(optArgin{jArg}, defaultValues{jArg}, validator{jArg});        
    end    
    parser.parse(varArgIn{optArgOrder(1:nArg)});  
else
    % we do have solve specific parameters. 
    % Add the setting for the detected direct input to the parser first
    optArgs = varArgIn(1:pSpos-1);
    varArgIn = varArgIn(pSpos:end);
    optArgOrder = 1:numel(optArgin);
    nOptArg = pSpos - 1;
    if emptyForDefault
        argDefault = cellfun(@isempty, optArgs);
        % move the empty positional arguments to parameter/value arguments
        optArgOrder = [columnVector(find(~argDefault)); columnVector(setdiff(1:numel(optArgin), find(~argDefault)))]';
        nOptArg = sum(~argDefault);
    end
    for jArg = optArgOrder(1:nOptArg)
        parser.addOptional(optArgin{jArg}, defaultValues{jArg}, validator{jArg});        
    end
    if mod(numel(varArgIn),2) == 1
        % this should indicate, that there is an LP solver struct somewhere!
        for i = 1:2:numel(varArgIn)
            if isstruct(varArgIn{i})
                % move the solver-specific parameter structure to the end
                varArgIn = [varArgIn(1:i-1),varArgIn(i+1:end),varArgIn(i)];
            end
        end
        if numel(varArgIn) > 1
            % both parameter-value inputs and parameter structure input
            % exist. Assume the parameter structure is solver-specific.
            % This is to allow control when function keywords coincide with
            % solver parameter names.
            knownSolverParamFields = fieldnames(varArgIn{end});
        end
    end
    
    % convert the input parameters into 2 x N [name; value] cell array
    nameValueParams = inputParamsToCells(varArgIn);
    % now, add the setting for the detected parameter-value inputs
    for jArg = optArgOrder((nOptArg + 1):numel(optArgin))
        parser.addParameter(optArgin{jArg}, defaultValues{jArg}, validator{jArg});
    end
    % and extract the parameters from the field names, as CaseSensitive = 0
    % only works for parameter/value pairs but not for fieldnames.
    functionParams = {};
    % build the parameter/value pairs array
    for i = 1:size(nameValueParams, 2)
        if ~any(strncmpi(nameValueParams{1, i}, optArgin, length(nameValueParams{1, i}))) ...
                || any(strcmp(knownSolverParamFields, nameValueParams{1, i}))
            % if it does not match any function keywords or is in the
            % solver-specific parameter structure
            otherParams.(nameValueParams{1, i}) = nameValueParams{2, i};
        else
            functionParams(end+1:end+2) = nameValueParams(:, i)';
        end
    end
    % and parse them.
    parser.CaseSensitive = 0;
    parser.parse(optArgs{optArgOrder(1:nOptArg)}, functionParams{:});
end

% fields in otherParams = cobraParams (name-value inputs for solveCobraXXX) + solver-specific parameter

% get the true solver-specific parameter structure by excluding all cobra options
% no need to protect assumed solver-specific parameters here because the format of cobra
% option keywords should not coincide with solver parameters (at least for gurobi and Cplex)
fieldToExclude = intersect(cobraOptions, fieldnames(otherParams));
solverParams = rmfield(otherParams, fieldToExclude);

% get the cobra parameters for each problem type.
[cobraParams, solverVarargin] = deal(struct());

for str = problemTypes
    cobraParams.(str{1}) = parseSolverParameters(str{1}, otherParams);
    tmp = [fieldnames(cobraParams.(str{1})), struct2cell(cobraParams.(str{1}))]';
    % get the varargin for each solver type
    solverVarargin.(str{1}) = [{solverParams}, tmp(:)'];
end

funParams = cellfun(@(x) parser.Results.(x), optArgin, 'UniformOutput', false);
end

function nameValueParams = inputParamsToCells(inputParams)
% convert the input parameters into 2 x N [name; value] cell array
[nameValueParams, paramErr] = deal({}, false);
for j = 1:2:numel(inputParams)
    if j < numel(inputParams)
        if ischar(inputParams{j})
            nameValueParams(:, end + 1) = columnVector(inputParams(j:(j + 1)));
        else
            paramErr = true;
            break
        end
    elseif isstruct(inputParams{j})
        nameValueParams = [nameValueParams, [columnVector(fieldnames(inputParams{j})), columnVector(struct2cell(inputParams{j}))]'];
    else
        paramErr = true;
    end
end
if paramErr
    error(sprintf(['Invalid Parameters supplied.\nParameters have to be supplied either as parameter/value pairs, or as struct.\n', ...
        'A combination is possible, if the last or first input argument is a struct, and all other arguments']))
end
end