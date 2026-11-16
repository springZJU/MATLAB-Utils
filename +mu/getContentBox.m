function [contentBox, elementBoxes] = getContentBox(figHandle, opts)
%GETCONTENTBOX Measure Position or TightInset content using layout roots.
%
%   contentBox = mu.getContentBox(figHandle)
%   [contentBox, elementBoxes] = mu.getContentBox(figHandle)
%   [...] = mu.getContentBox(..., Name, Value)
%
% The transform and annotation roots are deliberately coarse:
%
%   - if the figure contains one or more tiledlayout objects, only the
%     outermost tiledlayout objects are returned as roots;
%   - axes and nested tiledlayout objects inside those roots are measured
%     internally but are not returned or annotated individually;
%   - if the figure contains no tiledlayout, visible axes are returned as
%     roots.
%
% Public tiledlayout text is preserved. In TightInset mode, common Title,
% Subtitle, XLabel, and YLabel objects are included when their pixel bounds
% can be read. When MATLAB does not expose a usable bound, the corresponding
% side of the owning tiledlayout OuterPosition is used conservatively.
%
% All rectangles are figure-relative pixels:
%
%   [left, bottom, width, height]
%
% NAME-VALUE OPTIONS
%   PositionType
%       'position', default
%           Measure each root Position.
%
%       'tightinset'
%           For a tiledlayout root, measure the union of TightInset-expanded
%           descendant axes, visible legend/colorbar descendants, colorbar
%           labels, and public tiledlayout text. For axes roots, include each
%           axes TightInset plus visible legend/colorbar boxes and colorbar
%           labels.
%
%   Annotation
%       false, default
%           Clear existing diagnostic rectangles and do not draw new ones.
%
%       true
%           Replace existing diagnostics with dashed rectangles for each
%           returned root and each legend/colorbar Position, a dotted box
%           for a measurable colorbar Label in TightInset mode, and one thick
%           red rectangle for the total content union. Internal axes inside
%           a tiledlayout are never annotated individually.
%
%       'preserve'
%           Keep existing diagnostic rectangles unchanged. Use this for
%           auxiliary measurements that must not replace the currently
%           displayed boundary during an iterative export.
%
% OUTPUT
%   contentBox
%       Union of the selected root boxes and visible legend/colorbar boxes.
%
%   elementBoxes
%       Structure with fields:
%           units
%           positionType
%           rootMode
%           contentBox
%           items
%           byType
%           typeUnion
%           typeNames
%           decorations (raw positionBox, full box including colorbar tick
%           labels, tightBox including the colorbar Label, and component boxes)
%
% Each item contains both:
%
%   item.position
%       Root Position used when the root is adjusted.
%
%   item.box
%       Selected Position or TightInset measurement used for content sizing.

arguments
    figHandle         (1,1) matlab.ui.Figure

    opts.PositionType {mustBeMember(opts.PositionType, {'Position', 'TightInset', 'position', 'tightinset'})} = 'Position'
    opts.Annotation = false
end

positionType = lower(validatestring( ...
    opts.PositionType, ...
    {'position', 'tightinset'}, ...
    mfilename, ...
    'PositionType'));

annotationMode = local_parseAnnotationMode_(opts.Annotation);

debugTag = 'mu.getContentBox.annotation';

if ~strcmp(annotationMode, 'preserve')
    local_deleteAnnotations_(figHandle, debugTag);
end

drawnow;

allObjects = findall(figHandle);

layoutMask = false(numel(allObjects), 1);

for objectIndex = 1:numel(allObjects)
    layoutMask(objectIndex) = ...
        local_isTiledLayout_(allObjects(objectIndex)) && ...
        ~local_isInternalObject_(allObjects(objectIndex));
end

layoutHandles = allObjects(layoutMask);
rootLayoutHandles = gobjects(0);

for layoutIndex = 1:numel(layoutHandles)
    layoutHandle = layoutHandles(layoutIndex);

    if ~local_hasTiledLayoutAncestor_(layoutHandle, figHandle)
        rootLayoutHandles(end + 1, 1) = layoutHandle; 
    end
end

if ~isempty(rootLayoutHandles)
    rootMode = 'tiledlayout';
    rootHandles = rootLayoutHandles;
else
    rootMode = 'axes';
    rootHandles = gobjects(0);

    for objectIndex = 1:numel(allObjects)
        objectHandle = allObjects(objectIndex);

        if ~local_isAxesLike_(objectHandle) || ...
                local_isInternalObject_(objectHandle) || ...
                ~local_isRenderableAxes_(objectHandle)
            continue;
        end

        rootHandles(end + 1, 1) = objectHandle; 
    end
end

if isempty(rootHandles)
    error('getContentBox:NoMeasurementRoots', ...
        'No outermost tiledlayout or renderable axes root was found.');
end

items = struct( ...
    'handle', {}, ...
    'type', {}, ...
    'subtype', {}, ...
    'position', {}, ...
    'box', {}, ...
    'method', {}, ...
    'axesHandle', {}, ...
    'isMeasured', {}, ...
    'includedInContentBox', {});

for rootIndex = 1:numel(rootHandles)
    rootHandle = rootHandles(rootIndex);

    [positionBox, positionSuccess] = ...
        local_getRootPositionBox_(rootHandle, figHandle);

    if ~positionSuccess
        warning('getContentBox:PositionMeasurementFailed', ...
            'Could not measure Position for %s.', class(rootHandle));
        continue;
    end

    if strcmp(positionType, 'tightinset')
        if local_isTiledLayout_(rootHandle)
            [selectedBox, selectedSuccess] = ...
                local_getLayoutTightBox_(rootHandle, figHandle);
            method = [ ...
                'descendant axes TightInset union, public layout text, ' ...
                'and visible layout decorations'];
        else
            [selectedBox, selectedSuccess] = ...
                local_getAxesTightBox_(rootHandle, figHandle);
            method = 'axes Position expanded by TightInset';
        end
    else
        selectedBox = positionBox;
        selectedSuccess = true;
        method = 'root Position';
    end

    if ~selectedSuccess
        selectedBox = positionBox;
        method = [method, ' fallback to Position']; %#ok<*AGROW>
    end

    if local_isTiledLayout_(rootHandle)
        typeName = 'tiledlayout';
        axesHandle = [];
    else
        typeName = 'axes';
        axesHandle = rootHandle;
    end

    items(end + 1) = struct( ...
        'handle', rootHandle, ...
        'type', typeName, ...
        'subtype', class(rootHandle), ...
        'position', reshape(double(positionBox), 1, 4), ...
        'box', reshape(double(selectedBox), 1, 4), ...
        'method', method, ...
        'axesHandle', axesHandle, ...
        'isMeasured', true, ...
        'includedInContentBox', true);
end

if isempty(items)
    error('getContentBox:NoValidMeasurements', ...
        'No valid Position or TightInset root box was measured.');
end

% Decorations are measured separately from transform roots. They still
% contribute to the total content boundary, but are not added to items because
% exportFigure2PDF transforms their positions with the owning axes.
decorationItems = local_collectDecorationBoxes_(figHandle, allObjects);
selectedBoxes = vertcat(items.box);

for decorationIndex = 1:numel(decorationItems)
    if strcmp(positionType, 'tightinset')
        decorationBox = decorationItems(decorationIndex).tightBox;
    else
        decorationBox = decorationItems(decorationIndex).box;
    end

    if local_isValidBox_(decorationBox)
        selectedBoxes(end + 1, :) = ... %#ok<AGROW>
            reshape(double(decorationBox), 1, 4);
    end
end

contentBox = local_unionBoxes_(selectedBoxes);

typeNames = unique(string({items.type}), 'stable');
byType = struct;
typeUnion = struct;

for typeIndex = 1:numel(typeNames)
    typeName = typeNames(typeIndex);
    typeMask = strcmp(string({items.type}), typeName);
    typeBoxes = vertcat(items(typeMask).box);
    fieldName = matlab.lang.makeValidName(char(typeName));

    byType.(fieldName) = typeBoxes;
    typeUnion.(fieldName) = local_unionBoxes_(typeBoxes);
end

elementBoxes = struct;
elementBoxes.units = 'pixels';
elementBoxes.positionType = positionType;
elementBoxes.rootMode = rootMode;
elementBoxes.contentBox = contentBox;
elementBoxes.items = items;
elementBoxes.byType = byType;
elementBoxes.typeUnion = typeUnion;
elementBoxes.typeNames = cellstr(typeNames);

% Keep legend and colorbar boxes available separately from transform roots.
% `positionBox` is the raw graphics Position used by exportFigure2PDF.
% `box` is the full decoration boundary: for colorbars it includes the bar
% and its numeric tick labels. `tightBox` also includes a measurable Label.
elementBoxes.decorations = decorationItems;

elementBoxes.annotationAxes = [];
elementBoxes.annotationHandles = gobjects(0, 1);

switch annotationMode
    case 'on'
        annotationHandles = gobjects(0, 1);

        decorationTypeNames = strings(1, 0);
        if ~isempty(decorationItems)
            decorationTypeNames = unique( ...
                string({decorationItems.type}), 'stable');
        end

        typeColors = lines(max( ...
            1, numel(typeNames) + numel(decorationTypeNames)));

        % Draw measurement-root boxes.
        for itemIndex = 1:numel(items)
            typeIndex = find( ...
                typeNames == string(items(itemIndex).type), ...
                1, ...
                'first');

            annotationHandle = local_drawPixelBox_( ...
                figHandle, ...
                items(itemIndex).box, ...
                typeColors(typeIndex, :), ...
                '--', ...
                0.5, ...
                debugTag, ...
                sprintf('%s %s: %s', ...
                    positionType, ...
                    items(itemIndex).type, ...
                    items(itemIndex).subtype));

            if ~isempty(annotationHandle) && isgraphics(annotationHandle)
                annotationHandles(end + 1, 1) = ... %#ok<AGROW>
                    annotationHandle;
            end
        end

        % Draw each full legend/colorbar box. For colorbars, this includes the
        % numeric tick labels. In TightInset mode, draw the separate public
        % Label extent with a dotted line as well.
        for decorationIndex = 1:numel(decorationItems)
            decorationTypeIndex = find( ...
                decorationTypeNames == ...
                    string(decorationItems(decorationIndex).type), ...
                1, ...
                'first');
            colorIndex = numel(typeNames) + decorationTypeIndex;
            decorationColor = typeColors(colorIndex, :);

            annotationHandle = local_drawPixelBox_( ...
                figHandle, ...
                decorationItems(decorationIndex).box, ...
                decorationColor, ...
                '--', ...
                0.5, ...
                debugTag, ...
                sprintf('%s %s full box', ...
                    positionType, ...
                    decorationItems(decorationIndex).type));

            if ~isempty(annotationHandle) && isgraphics(annotationHandle)
                annotationHandles(end + 1, 1) = ... %#ok<AGROW>
                    annotationHandle;
            end

            if strcmp(positionType, 'tightinset') && ...
                    local_isValidBox_( ...
                        decorationItems(decorationIndex).labelBox)
                annotationHandle = local_drawPixelBox_( ...
                    figHandle, ...
                    decorationItems(decorationIndex).labelBox, ...
                    decorationColor, ...
                    ':', ...
                    0.75, ...
                    debugTag, ...
                    'colorbar Label extent');

                if ~isempty(annotationHandle) && isgraphics(annotationHandle)
                    annotationHandles(end + 1, 1) = ... %#ok<AGROW>
                        annotationHandle;
                end
            end
        end

        annotationHandle = local_drawPixelBox_( ...
            figHandle, ...
            contentBox, ...
            [1, 0, 0], ...
            '-', ...
            1, ...
            debugTag, ...
            sprintf('total %s box', positionType));

        if ~isempty(annotationHandle) && isgraphics(annotationHandle)
            annotationHandles(end + 1, 1) = annotationHandle;
        end

        elementBoxes.annotationHandles = annotationHandles;
        drawnow;

    case 'preserve'
        elementBoxes.annotationHandles = ...
            findall(figHandle, 'Tag', debugTag);
        elementBoxes.annotationHandles = ...
            elementBoxes.annotationHandles(:);

    otherwise
        % Annotation mode 'off': old diagnostics were already removed.
end

end

function decorationItems = ...
        local_collectDecorationBoxes_(figHandle, allObjects)
%LOCAL_COLLECTDECORATIONBOXES_ Collect full legend/colorbar boundaries.
%
% positionBox is the object's actual Position and is used when transforming
% graphics objects. For a colorbar, box additionally includes the rendered
% numeric tick-label region, and tightBox additionally includes the public
% colorbar Label. All boxes use figure-relative pixels.

decorationItems = struct( ...
    'handle', {}, ...
    'type', {}, ...
    'positionBox', {}, ...
    'box', {}, ...
    'tightBox', {}, ...
    'tickLabelBox', {}, ...
    'tickLabels', {}, ...
    'labelHandle', {}, ...
    'labelBox', {});

for objectIndex = 1:numel(allObjects)
    objectHandle = allObjects(objectIndex);

    if ~local_isDecoration_(objectHandle) || ...
            ~local_isVisibleObject_(objectHandle) || ...
            ~isprop(objectHandle, 'Position') || ...
            ~isprop(objectHandle, 'Units')
        continue;
    end

    className = lower(class(objectHandle));

    if contains(className, 'colorbar')
        typeName = 'colorbar';
    elseif contains(className, 'legend')
        typeName = 'legend';
    else
        continue;
    end

    [positionBox, positionSuccess] = ...
        local_getGenericAbsolutePositionBox_(objectHandle, figHandle);

    if ~positionSuccess
        continue;
    end

    box = reshape(double(positionBox), 1, 4);
    tightBox = box;
    tickLabelBox = nan(1, 4);
    tickLabels = strings(0, 1);
    labelHandle = [];
    labelBox = nan(1, 4);

    if strcmp(typeName, 'colorbar')
        [tickLabelBox, tickLabelSuccess, tickLabels] = ...
            local_getColorbarTickLabelBox_( ...
                objectHandle, figHandle, positionBox);

        if tickLabelSuccess
            box = local_unionBoxes_([box; tickLabelBox]);
            tightBox = box;
        end

        [labelBox, labelSuccess, labelHandle] = ...
            local_getColorbarLabelBox_(objectHandle, figHandle);

        if labelSuccess
            tightBox = local_unionBoxes_([tightBox; labelBox]);
        end
    end

    decorationItems(end + 1) = struct( ... %#ok<AGROW>
        'handle', objectHandle, ...
        'type', typeName, ...
        'positionBox', reshape(double(positionBox), 1, 4), ...
        'box', reshape(double(box), 1, 4), ...
        'tightBox', reshape(double(tightBox), 1, 4), ...
        'tickLabelBox', reshape(double(tickLabelBox), 1, 4), ...
        'tickLabels', tickLabels, ...
        'labelHandle', labelHandle, ...
        'labelBox', reshape(double(labelBox), 1, 4));
end

end


function [tickLabelBox, success, tickLabels] = ...
        local_getColorbarTickLabelBox_(colorbarHandle, figHandle, positionBox)
%LOCAL_GETCOLORBARTICKLABELBOX_ Estimate the full rendered numeric label box.
%
% ColorBar numeric tick labels are generally drawn by its ruler and are not
% exposed as ordinary Text children. Measure the actual TickLabels strings
% with a temporary text object using the colorbar's font settings, then
% place a conservative label envelope outside the bar based on orientation
% and Location. The temporary measurement axes is deleted before returning.

tickLabelBox = nan(1, 4);
success = false;
tickLabels = local_getColorbarTickLabels_(colorbarHandle);

if isempty(tickLabels)
    return;
end

[maxTextWidthPx, maxTextHeightPx, measureSuccess] = ...
    local_measureColorbarTickLabelsPx_( ...
        colorbarHandle, figHandle, tickLabels);

if ~measureSuccess || ...
        any(~isfinite(positionBox)) || ...
        any(positionBox(3:4) <= 0)
    return;
end

orientation = 'vertical';
if isprop(colorbarHandle, 'Orientation')
    try
        orientation = lower(char(string(colorbarHandle.Orientation)));
    catch
    end
elseif positionBox(3) > positionBox(4)
    orientation = 'horizontal';
end

location = '';
if isprop(colorbarHandle, 'Location')
    try
        location = lower(char(string(colorbarHandle.Location)));
    catch
    end
end

fontSizePx = local_getColorbarFontSizePx_(colorbarHandle, figHandle, positionBox);
gapPx = max(3, 0.25 * fontSizePx);

if contains(orientation, 'vertical')
    tickSide = local_getColorbarTickLabelSide_( ...
        colorbarHandle, figHandle, positionBox, location, 'vertical');

    labelHeight = maxTextHeightPx;
    labelWidth = maxTextWidthPx;

    if strcmp(tickSide, 'left')
        labelLeft = positionBox(1) - gapPx - labelWidth;
    else
        labelLeft = positionBox(1) + positionBox(3) + gapPx;
    end

    tickLabelBox = [ ...
        labelLeft, ...
        positionBox(2) - labelHeight / 2, ...
        labelWidth, ...
        positionBox(4) + labelHeight];
else
    tickSide = local_getColorbarTickLabelSide_( ...
        colorbarHandle, figHandle, positionBox, location, 'horizontal');

    labelWidth = maxTextWidthPx;
    labelHeight = maxTextHeightPx;

    if strcmp(tickSide, 'above')
        labelBottom = positionBox(2) + positionBox(4) + gapPx;
    else
        labelBottom = positionBox(2) - gapPx - labelHeight;
    end

    tickLabelBox = [ ...
        positionBox(1) - labelWidth / 2, ...
        labelBottom, ...
        positionBox(3) + labelWidth, ...
        labelHeight];
end

% A small pad protects anti-aliased glyph edges and minor ruler spacing
% differences between screen rendering and export rendering.
padPx = 1;
tickLabelBox = [ ...
    tickLabelBox(1) - padPx, ...
    tickLabelBox(2) - padPx, ...
    tickLabelBox(3) + 2 * padPx, ...
    tickLabelBox(4) + 2 * padPx];

success = local_isValidBox_(tickLabelBox);

end


function tickLabels = local_getColorbarTickLabels_(colorbarHandle)
%LOCAL_GETCOLORBARTICKLABELS_ Read rendered tick strings when available.

tickLabels = strings(0, 1);

if isprop(colorbarHandle, 'TickLabels')
    try
        rawLabels = colorbarHandle.TickLabels;

        if ischar(rawLabels)
            tickLabels = string(cellstr(rawLabels));
        elseif iscell(rawLabels)
            tickLabels = string(rawLabels(:));
        elseif isstring(rawLabels)
            tickLabels = rawLabels(:);
        elseif isnumeric(rawLabels)
            tickLabels = string(rawLabels(:));
        end

        tickLabels = strtrim(tickLabels(:));
        tickLabels = tickLabels(strlength(tickLabels) > 0);
    catch
        tickLabels = strings(0, 1);
    end
end

% Some releases expose generated labels only when TickLabelsMode is 'auto'.
% In that case, use the current tick values as a conservative fallback.
if isempty(tickLabels) && ...
        isprop(colorbarHandle, 'TickLabelsMode') && ...
        isprop(colorbarHandle, 'Ticks')
    try
        labelsMode = lower(char(string(colorbarHandle.TickLabelsMode)));
        if strcmp(labelsMode, 'auto')
            tickValues = double(colorbarHandle.Ticks(:));
            tickValues = tickValues(isfinite(tickValues));
            tickLabels = compose('%.6g', tickValues);
        end
    catch
        tickLabels = strings(0, 1);
    end
end

end


function [maxWidthPx, maxHeightPx, success] = ...
        local_measureColorbarTickLabelsPx_(colorbarHandle, figHandle, tickLabels)
%LOCAL_MEASURECOLORBARTICKLABELSPX_ Measure label strings using MATLAB text.

maxWidthPx = nan;
maxHeightPx = nan;
success = false;

try
    figureSize = local_getFigureSizePx_(figHandle);
    currentAxes = figHandle.CurrentAxes;
catch
    figureSize = [800, 600];
    currentAxes = [];
end

measureAxes = [];
textHandle = [];

try
    measureAxes = axes( ...
        'Parent', figHandle, ...
        'Units', 'pixels', ...
        'Position', [1, 1, max(figureSize(1), 200), max(figureSize(2), 200)], ...
        'Visible', 'off', ...
        'HandleVisibility', 'off', ...
        'Tag', 'mu.getContentBox.measurement');

    textProperties = { ...
        'Parent', measureAxes, ...
        'Units', 'pixels', ...
        'Position', [2, 2, 0], ...
        'Visible', 'on', ...
        'Clipping', 'off'};

    if isprop(colorbarHandle, 'FontName')
        textProperties(end + 1:end + 2) = ...
            {'FontName', colorbarHandle.FontName};
    end
    % Set FontUnits before FontSize so MATLAB interprets FontSize in the
    % same unit system as the source colorbar.
    if isprop(colorbarHandle, 'FontUnits')
        textProperties(end + 1:end + 2) = ...
            {'FontUnits', colorbarHandle.FontUnits};
    end
    if isprop(colorbarHandle, 'FontSize')
        textProperties(end + 1:end + 2) = ...
            {'FontSize', colorbarHandle.FontSize};
    end
    if isprop(colorbarHandle, 'FontWeight')
        textProperties(end + 1:end + 2) = ...
            {'FontWeight', colorbarHandle.FontWeight};
    end
    if isprop(colorbarHandle, 'FontAngle')
        textProperties(end + 1:end + 2) = ...
            {'FontAngle', colorbarHandle.FontAngle};
    end
    if isprop(colorbarHandle, 'TickLabelInterpreter')
        textProperties(end + 1:end + 2) = ...
            {'Interpreter', colorbarHandle.TickLabelInterpreter};
    end

    textHandle = text(textProperties{:}, 'String', '0');

    maxWidthPx = 0;
    maxHeightPx = 0;

    for labelIndex = 1:numel(tickLabels)
        textHandle.String = char(tickLabels(labelIndex));
        drawnow;

        extentPx = reshape(double(textHandle.Extent), 1, 4);

        if numel(extentPx) ~= 4 || ...
                any(~isfinite(extentPx)) || ...
                any(extentPx(3:4) <= 0)
            continue;
        end

        maxWidthPx = max(maxWidthPx, extentPx(3));
        maxHeightPx = max(maxHeightPx, extentPx(4));
    end

    success = isfinite(maxWidthPx) && isfinite(maxHeightPx) && ...
        maxWidthPx > 0 && maxHeightPx > 0;
catch
    success = false;
end

% Remove the temporary measurement axes immediately and restore CurrentAxes.
if ~isempty(measureAxes) && isgraphics(measureAxes)
    try
        delete(measureAxes);
    catch
    end
end

if ~isempty(currentAxes) && isgraphics(currentAxes)
    try
        figHandle.CurrentAxes = currentAxes;
    catch
    end
end

end


function fontSizePx = local_getColorbarFontSizePx_( ...
        colorbarHandle, figHandle, positionBox)
%LOCAL_GETCOLORBARFONTSIZEPX_ Estimate the displayed font size in pixels.

fontSizePx = 12;

try
    if isprop(colorbarHandle, 'FontSize')
        fontSizeValue = double(colorbarHandle.FontSize);
    else
        fontSizeValue = 9;
    end

    fontUnits = 'points';
    if isprop(colorbarHandle, 'FontUnits')
        fontUnits = lower(char(string(colorbarHandle.FontUnits)));
    end

    screenPpi = double(get(groot, 'ScreenPixelsPerInch'));
    if ~isfinite(screenPpi) || screenPpi <= 0
        screenPpi = 96;
    end

    switch fontUnits
        case 'pixels'
            fontSizePx = fontSizeValue;
        case 'inches'
            fontSizePx = fontSizeValue * screenPpi;
        case 'centimeters'
            fontSizePx = fontSizeValue * screenPpi / 2.54;
        case 'normalized'
            fontSizePx = fontSizeValue * max(1, min(positionBox(3:4)));
        otherwise
            fontSizePx = fontSizeValue * screenPpi / 72;
    end
catch
    fontSizePx = 12;
end

fontSizePx = max(1, fontSizePx);

end


function tickSide = local_getColorbarTickLabelSide_( ...
        colorbarHandle, figHandle, positionBox, location, orientation)
%LOCAL_GETCOLORBARTICKLABELSIDE_ Infer which side contains numeric labels.

if strcmp(orientation, 'vertical')
    if contains(location, 'west')
        tickSide = 'left';
        return;
    elseif contains(location, 'east')
        tickSide = 'right';
        return;
    end
else
    if contains(location, 'north')
        tickSide = 'above';
        return;
    elseif contains(location, 'south')
        tickSide = 'below';
        return;
    end
end

% For manually positioned colorbars, compare the colorbar to its owner axes.
ownerAxes = [];
if isprop(colorbarHandle, 'Axes')
    try
        ownerAxes = colorbarHandle.Axes;
    catch
    end
end

if ~isempty(ownerAxes) && isgraphics(ownerAxes)
    [ownerBox, ownerSuccess] = ...
        local_getGenericAbsolutePositionBox_(ownerAxes, figHandle);
else
    ownerBox = nan(1, 4);
    ownerSuccess = false;
end

if ownerSuccess
    if strcmp(orientation, 'vertical')
        colorbarCenter = positionBox(1) + positionBox(3) / 2;
        ownerCenter = ownerBox(1) + ownerBox(3) / 2;
        if colorbarCenter < ownerCenter
            tickSide = 'left';
        else
            tickSide = 'right';
        end
    else
        colorbarCenter = positionBox(2) + positionBox(4) / 2;
        ownerCenter = ownerBox(2) + ownerBox(4) / 2;
        if colorbarCenter > ownerCenter
            tickSide = 'above';
        else
            tickSide = 'below';
        end
    end
else
    if strcmp(orientation, 'vertical')
        tickSide = 'right';
    else
        tickSide = 'below';
    end
end

end


function [positionBox, success] = ...
        local_getRootPositionBox_(rootHandle, figHandle)
%LOCAL_GETROOTPOSITIONBOX_ Measure a root Position in figure pixels.

if local_isTiledLayout_(rootHandle)
    [positionBox, success] = ...
        local_getLayoutPositionBox_(rootHandle, figHandle);
else
    [positionBox, success] = ...
        local_getAxesPositionBox_(rootHandle, figHandle);
end

end

function [positionBox, success] = ...
        local_getLayoutPositionBox_(layoutHandle, figHandle)
%LOCAL_GETLAYOUTPOSITIONBOX_ Read tiledlayout Position as figure-relative.
%
% Nested tiledlayout Position values are treated as figure-relative. The
% recursive GETPIXELPOSITION result is preferred because it does not require
% changing layout Units.

positionBox = nan(1, 4);
success = false;

try
    positionBox = reshape( ...
        double(getpixelposition(layoutHandle, true)), ...
        1, 4);

    success = local_isValidBox_(positionBox);

    if success
        return;
    end
catch
end

if ~isprop(layoutHandle, 'Position') || ...
        ~isprop(layoutHandle, 'Units')
    return;
end

try
    positionBox = hgconvertunits( ...
        figHandle, ...
        double(layoutHandle.Position), ...
        char(string(layoutHandle.Units)), ...
        'pixels', ...
        figHandle);

    positionBox = reshape(double(positionBox), 1, 4);
    success = local_isValidBox_(positionBox);
catch
end

end

function [outerBox, success] = ...
        local_getLayoutOuterBox_(layoutHandle, figHandle)
%LOCAL_GETLAYOUTOUTERBOX_ Read tiledlayout OuterPosition in figure pixels.
%
% The layout units are never changed. Nested layout OuterPosition is treated
% as figure-relative.

outerBox = nan(1, 4);
success = false;

if ~isprop(layoutHandle, 'OuterPosition') || ...
        ~isprop(layoutHandle, 'Units')
    [outerBox, success] = ...
        local_getLayoutPositionBox_(layoutHandle, figHandle);
    return;
end

try
    outerBox = hgconvertunits( ...
        figHandle, ...
        double(layoutHandle.OuterPosition), ...
        char(string(layoutHandle.Units)), ...
        'pixels', ...
        figHandle);

    outerBox = reshape(double(outerBox), 1, 4);
    success = local_isValidBox_(outerBox);
catch
end

if ~success
    [outerBox, success] = ...
        local_getLayoutPositionBox_(layoutHandle, figHandle);
end

end

function [positionBox, success] = ...
        local_getAxesPositionBox_(axesHandle, figHandle)
%LOCAL_GETAXESPOSITIONBOX_ Read axes Position in figure pixels.
%
% For axes parented by tiledlayout, Position and TightInset are interpreted
% relative to the direct parent tiledlayout OuterPosition.

positionBox = nan(1, 4);
success = false;
parentHandle = local_parent_(axesHandle);

if local_isTiledLayout_(parentHandle)
    [layoutOuterBox, layoutSuccess] = ...
        local_getLayoutOuterBox_(parentHandle, figHandle);

    if ~layoutSuccess
        return;
    end

    [rawPositionPx, rawSuccess] = ...
        local_getAxesPixelGeometry_(axesHandle);

    if ~rawSuccess
        return;
    end

    positionBox = [ ...
        layoutOuterBox(1:2) + ...
            rawPositionPx(1:2) - [1, 1], ...
        rawPositionPx(3:4)];

    success = local_isValidBox_(positionBox);
    return;
end

try
    positionBox = reshape( ...
        double(getpixelposition(axesHandle, true)), ...
        1, 4);

    success = local_isValidBox_(positionBox);

    if success
        return;
    end
catch
end

[positionBox, success] = ...
    local_getGenericAbsolutePositionBox_(axesHandle, figHandle);

end

function [tightBox, success] = ...
        local_getAxesTightBox_(axesHandle, figHandle)
%LOCAL_GETAXESTIGHTBOX_ Expand absolute axes Position by TightInset.

tightBox = nan(1, 4);
success = false;

[positionBox, positionSuccess] = ...
    local_getAxesPositionBox_(axesHandle, figHandle);

if ~positionSuccess
    return;
end

[~, tightInsetPx, geometrySuccess] = ...
    local_getAxesPixelGeometry_(axesHandle);

if ~geometrySuccess || ...
        any(~isfinite(tightInsetPx)) || ...
        any(tightInsetPx < 0)
    tightBox = positionBox;
    success = true;
    return;
end

tightBox = [ ...
    positionBox(1) - tightInsetPx(1), ...
    positionBox(2) - tightInsetPx(2), ...
    positionBox(3) + tightInsetPx(1) + tightInsetPx(3), ...
    positionBox(4) + tightInsetPx(2) + tightInsetPx(4)];

success = local_isValidBox_(tightBox);

end

function [positionPx, tightInsetPx, success] = ...
        local_getAxesPixelGeometry_(axesHandle)
%LOCAL_GETAXESPIXELGEOMETRY_ Read Position and TightInset in pixel units.
%
% The axes Units value is restored immediately. DRAWNOW is never called while
% Units='pixels'.

positionPx = nan(1, 4);
tightInsetPx = nan(1, 4);
success = false;

if ~isprop(axesHandle, 'Units') || ...
        ~isprop(axesHandle, 'Position')
    return;
end

try
    originalUnits = axesHandle.Units;
    cleanupObj = onCleanup(@() ...
        local_restoreUnits_(axesHandle, originalUnits)); 

    axesHandle.Units = 'pixels';
    positionPx = reshape(double(axesHandle.Position), 1, 4);

    if isprop(axesHandle, 'TightInset')
        tightInsetPx = reshape(double(axesHandle.TightInset), 1, 4);
    else
        tightInsetPx = zeros(1, 4);
    end

    success = ...
        local_isValidBox_(positionPx) && ...
        all(isfinite(tightInsetPx));
catch
end

end

function [tightBox, success] = ...
        local_getLayoutTightBox_(layoutHandle, figHandle)
%LOCAL_GETLAYOUTTIGHTBOX_ Measure content inside one tiledlayout root.
%
% Descendant axes are measured but are not returned as separate root items.

tightBoxes = zeros(0, 4);
descendants = findall(layoutHandle);

for objectIndex = 1:numel(descendants)
    objectHandle = descendants(objectIndex);

    if local_isAxesLike_(objectHandle) && ...
            ~local_isInternalObject_(objectHandle) && ...
            local_isRenderableAxes_(objectHandle)
        [axesTightBox, axesSuccess] = ...
            local_getAxesTightBox_(objectHandle, figHandle);

        if axesSuccess
            tightBoxes(end + 1, :) = axesTightBox; 
        end

    elseif local_isDecoration_(objectHandle) && ...
            local_isVisibleObject_(objectHandle)
        [decorationBox, decorationSuccess] = ...
            local_getDecorationTightBox_(objectHandle, figHandle);

        if decorationSuccess
            tightBoxes(end + 1, :) = decorationBox; 
        end
    end
end

if isempty(tightBoxes)
    [tightBox, success] = ...
        local_getLayoutPositionBox_(layoutHandle, figHandle);
else
    tightBox = local_unionBoxes_(tightBoxes);
    success = local_isValidBox_(tightBox);
end

layoutObjects = descendants( ...
    arrayfun(@local_isTiledLayout_, descendants));

if ~any(layoutObjects == layoutHandle)
    layoutObjects(end + 1, 1) = layoutHandle;
end

for layoutIndex = 1:numel(layoutObjects)
    [tightBox, success] = local_includeLayoutPublicText_( ...
        layoutObjects(layoutIndex), ...
        tightBox, ...
        success, ...
        figHandle);
end

end

function [boundaryBox, success] = local_includeLayoutPublicText_( ...
        layoutHandle, boundaryBox, success, figHandle)
%LOCAL_INCLUDELAYOUTPUBLICTEXT_ Include common tiledlayout text conservatively.

propertyNames = {'Title', 'Subtitle', 'XLabel', 'YLabel'};
sideNames = {'top', 'top', 'bottom', 'left'};

[outerBox, outerSuccess] = ...
    local_getLayoutOuterBox_(layoutHandle, figHandle);

for propertyIndex = 1:numel(propertyNames)
    propertyName = propertyNames{propertyIndex};

    if ~isprop(layoutHandle, propertyName)
        continue;
    end

    try
        textHandle = layoutHandle.(propertyName);
    catch
        continue;
    end

    if isempty(textHandle) || ...
            ~isgraphics(textHandle) || ...
            ~local_hasTextContent_(textHandle)
        continue;
    end

    [textBox, textSuccess] = ...
        local_getGenericAbsolutePositionBox_( ...
            textHandle, figHandle);

    if textSuccess
        if success
            boundaryBox = local_unionBoxes_([boundaryBox; textBox]);
        else
            boundaryBox = textBox;
            success = true;
        end

        continue;
    end

    if ~outerSuccess
        continue;
    end

    if ~success
        boundaryBox = outerBox;
        success = true;
        continue;
    end

    leftValue = boundaryBox(1);
    bottomValue = boundaryBox(2);
    rightValue = boundaryBox(1) + boundaryBox(3);
    topValue = boundaryBox(2) + boundaryBox(4);

    switch sideNames{propertyIndex}
        case 'top'
            topValue = max( ...
                topValue, ...
                outerBox(2) + outerBox(4));

        case 'bottom'
            bottomValue = min(bottomValue, outerBox(2));

        case 'left'
            leftValue = min(leftValue, outerBox(1));
    end

    boundaryBox = [ ...
        leftValue, ...
        bottomValue, ...
        rightValue - leftValue, ...
        topValue - bottomValue];
end

end

function [tightBox, success] = ...
        local_getDecorationTightBox_(objectHandle, figHandle)
%LOCAL_GETDECORATIONTIGHTBOX_ Include a colorbar Label when measurable.

[tightBox, success] = ...
    local_getGenericAbsolutePositionBox_(objectHandle, figHandle);

if ~success || ~contains(lower(class(objectHandle)), 'colorbar')
    return;
end

% Include the numeric tick labels in the colorbar's tight boundary, not just
% the narrow color ramp rectangle.
[tickLabelBox, tickLabelSuccess] = ...
    local_getColorbarTickLabelBox_(objectHandle, figHandle, tightBox);

if tickLabelSuccess
    tightBox = local_unionBoxes_([tightBox; tickLabelBox]);
end

% The public ColorBar.Label is a separate text object and may extend farther
% than both the color ramp and its numeric tick labels.
[labelBox, labelSuccess] = ...
    local_getColorbarLabelBox_(objectHandle, figHandle);

if labelSuccess
    tightBox = local_unionBoxes_([tightBox; labelBox]);
end

success = local_isValidBox_(tightBox);

end


function [labelBox, success, labelHandle] = ...
        local_getColorbarLabelBox_(colorbarHandle, figHandle)
%LOCAL_GETCOLORBARLABELBOX_ Measure a colorbar Label's rendered text extent.
%
% ColorBar does not expose a TightInset property. Its Label is a Text object;
% temporarily switching the label's Units to pixels lets MATLAB report the
% text Extent in the label parent's local pixel coordinates. The original
% Units value is restored immediately and no DRAWNOW is issued while changed.

labelBox = nan(1, 4);
success = false;
labelHandle = [];

if ~isprop(colorbarHandle, 'Label')
    return;
end

try
    labelHandle = colorbarHandle.Label;
catch
    return;
end

if isempty(labelHandle) || ...
        ~isgraphics(labelHandle) || ...
        ~local_isVisibleObject_(labelHandle) || ...
        ~local_hasTextContent_(labelHandle) || ...
        ~isprop(labelHandle, 'Units') || ...
        ~isprop(labelHandle, 'Extent')
    return;
end

parentHandle = local_parent_(labelHandle);
parentSuccess = false;
parentBox = nan(1, 4);

if ~isempty(parentHandle) && isgraphics(parentHandle)
    [parentBox, parentSuccess] = ...
        local_getGenericAbsolutePositionBox_(parentHandle, figHandle);
end

if ~parentSuccess
    % Some MATLAB releases expose a non-container Label parent. In that
    % case, use the ColorBar Position as the local pixel-coordinate origin.
    [parentBox, parentSuccess] = ...
        local_getGenericAbsolutePositionBox_(colorbarHandle, figHandle);
end

if ~parentSuccess
    return;
end

try
    originalUnits = labelHandle.Units;
    cleanupObj = onCleanup(@() ...
        local_restoreUnits_(labelHandle, originalUnits));

    labelHandle.Units = 'pixels';
    extentPx = reshape(double(labelHandle.Extent), 1, 4);

    clear cleanupObj;
catch
    return;
end

if numel(extentPx) ~= 4 || ...
        any(~isfinite(extentPx)) || ...
        any(extentPx(3:4) <= 0)
    return;
end

% Text Extent is parent-local when Units='pixels'. Convert it to the same
% figure-relative pixel coordinates used by the decoration Position boxes.
labelBox = [ ...
    parentBox(1:2) + extentPx(1:2) - [1, 1], ...
    extentPx(3:4)];

% A one-pixel pad protects antialiased glyph edges during raster/PDF export.
labelBox = [ ...
    labelBox(1) - 1, ...
    labelBox(2) - 1, ...
    labelBox(3) + 2, ...
    labelBox(4) + 2];

success = local_isValidBox_(labelBox);

end


function [positionBox, success] = ...
        local_getGenericAbsolutePositionBox_(objectHandle, figHandle)
%LOCAL_GETGENERICABSOLUTEPOSITIONBOX_ Read positioned objects recursively.

positionBox = nan(1, 4);
success = false;

try
    positionBox = reshape( ...
        double(getpixelposition(objectHandle, true)), ...
        1, 4);

    success = local_isValidBox_(positionBox);

    if success
        return;
    end
catch
end

if ~isprop(objectHandle, 'Position') || ...
        ~isprop(objectHandle, 'Units')
    return;
end

try
    nativePosition = reshape(double(objectHandle.Position), 1, 4);
    nativeUnits = char(string(objectHandle.Units));
    parentHandle = local_parent_(objectHandle);

    localPosition = hgconvertunits( ...
        figHandle, ...
        nativePosition, ...
        nativeUnits, ...
        'pixels', ...
        parentHandle);

    localPosition = reshape(double(localPosition), 1, 4);

    if ~local_isValidBox_(localPosition)
        return;
    end

    if isempty(parentHandle) || isequal(parentHandle, figHandle)
        positionBox = localPosition;
    else
        [parentBox, parentSuccess] = ...
            local_getGenericAbsolutePositionBox_( ...
                parentHandle, figHandle);

        if ~parentSuccess
            return;
        end

        positionBox = [ ...
            parentBox(1:2) + localPosition(1:2) - [1, 1], ...
            localPosition(3:4)];
    end

    success = local_isValidBox_(positionBox);
catch
end

end

function tf = local_hasTiledLayoutAncestor_(objectHandle, figHandle)
%LOCAL_HASTILEDLAYOUTANCESTOR_ Detect a tiledlayout ancestor.

tf = false;
parentHandle = local_parent_(objectHandle);

while ~isempty(parentHandle) && ~isequal(parentHandle, figHandle)
    if local_isTiledLayout_(parentHandle)
        tf = true;
        return;
    end

    parentHandle = local_parent_(parentHandle);
end

end

function tf = local_isTiledLayout_(objectHandle)
%LOCAL_ISTILEDLAYOUT_ Identify TiledChartLayout objects.

tf = isa(objectHandle, ...
    'matlab.graphics.layout.TiledChartLayout');

end

function tf = local_isAxesLike_(objectHandle)
%LOCAL_ISAXESLIKE_ Identify public axes objects.

className = lower(class(objectHandle));

tf = ...
    isa(objectHandle, 'matlab.graphics.axis.AbstractAxes') || ...
    contains(className, 'matlab.graphics.axis.axes') || ...
    contains(className, 'matlab.graphics.axis.polaraxes') || ...
    contains(className, 'matlab.graphics.axis.geographicaxes');

if contains(className, '.internal.') || ...
        contains(className, '.decorator.')
    tf = false;
end

end

function tf = local_isRenderableAxes_(axesHandle)
%LOCAL_ISRENDERABLEAXES_ Determine whether an axes contributes content.

tf = false;

try
    if isprop(axesHandle, 'Visible') && ...
            strcmpi(char(string(axesHandle.Visible)), 'on')
        tf = true;
    end
catch
end

if tf
    return;
end

try
    tf = any(isgraphics(axesHandle.Children));
catch
end

end

function tf = local_isDecoration_(objectHandle)
%LOCAL_ISDECORATION_ Identify visible legend and colorbar objects.

className = lower(class(objectHandle));

tf = ...
    contains(className, 'illustration.legend') || ...
    contains(className, 'illustration.colorbar') || ...
    endsWith(className, '.legend') || ...
    endsWith(className, '.colorbar');

end

function tf = local_isVisibleObject_(objectHandle)
%LOCAL_ISVISIBLEOBJECT_ Check public graphics visibility.

tf = true;

if isprop(objectHandle, 'Visible')
    try
        tf = strcmpi(char(string(objectHandle.Visible)), 'on');
    catch
    end
end

end

function tf = local_hasTextContent_(textHandle)
%LOCAL_HASTEXTCONTENT_ Test whether a public text object contains text.

tf = false;

if ~isprop(textHandle, 'String')
    return;
end

try
    textValue = string(textHandle.String);
    tf = any(strlength(textValue) > 0);
catch
end

end

function tf = local_isInternalObject_(objectHandle)
%LOCAL_ISINTERNALOBJECT_ Exclude toolbar and interaction implementation data.

className = lower(class(objectHandle));

tf = ...
    contains(className, '.internal.') || ...
    contains(className, '.interaction.') || ...
    contains(className, '.toolbar.') || ...
    contains(className, 'matlab.graphics.shape.internal.');

% Exclude the diagnostic overlay axes and its tagged children from future
% measurement passes, so Annotation=true never changes the measured result.
try
    tagValue = char(string(objectHandle.Tag));

    if strcmp(tagValue, 'mu.getContentBox.annotation') || ...
            startsWith(tagValue, 'mu.getContentBox.annotation.')
        tf = true;
    end
catch
end

end

function parentHandle = local_parent_(objectHandle)
%LOCAL_PARENT_ Return Parent when available.

parentHandle = [];

try
    parentHandle = objectHandle.Parent;
catch
end

end

function boundaryBox = local_unionBoxes_(boxes)
%LOCAL_UNIONBOXES_ Calculate the union of valid boxes.

if isempty(boxes)
    boundaryBox = [];
    return;
end

validMask = false(size(boxes, 1), 1);

for boxIndex = 1:size(boxes, 1)
    validMask(boxIndex) = local_isValidBox_(boxes(boxIndex, :));
end

boxes = boxes(validMask, :);

if isempty(boxes)
    boundaryBox = [];
    return;
end

leftValue = min(boxes(:, 1));
bottomValue = min(boxes(:, 2));
rightValue = max(boxes(:, 1) + boxes(:, 3));
topValue = max(boxes(:, 2) + boxes(:, 4));

boundaryBox = [ ...
    leftValue, ...
    bottomValue, ...
    rightValue - leftValue, ...
    topValue - bottomValue];

end

function annotationMode = local_parseAnnotationMode_(value)
%LOCAL_PARSEANNOTATIONMODE_ Parse logical and named annotation modes.

if islogical(value) && isscalar(value)
    if value
        annotationMode = 'on';
    else
        annotationMode = 'off';
    end
    return;
end

if ischar(value) || (isstring(value) && isscalar(value))
    annotationMode = lower(strtrim(char(string(value))));

    if any(strcmp(annotationMode, {'on', 'off', 'preserve'}))
        return;
    end
end

error('getContentBox:InvalidAnnotationOption', ...
    ['Annotation must be logical true/false or one of the text values ' ...
     '''on'', ''off'', or ''preserve''.']);
end


function annotationHandle = local_drawPixelBox_( ...
        figHandle, rawBox, lineColor, lineStyle, lineWidth, ...
        debugTag, description)
%LOCAL_DRAWPIXELBOX_ Draw a clipped figure-relative annotation rectangle.
%
% This is the original annotation-object implementation. In particular, the
% rectangle is a child of the figure's annotation layer, not a new overlay
% axes, so it does not affect axes/layout measurement or CurrentAxes.

annotationHandle = gobjects(0, 1);

if ~local_isValidBox_(rawBox)
    return;
end

figureSize = local_getFigureSizePx_(figHandle);

if numel(figureSize) ~= 2 || ...
        any(~isfinite(figureSize)) || ...
        any(figureSize <= 0)
    warning('getContentBox:AnnotationFigureSizeFailed', ...
        'Could not determine the figure size for diagnostic annotations.');
    return;
end

% Annotation Position in pixel units uses a figure-relative coordinate
% system whose lower-left corner is [0, 0]. Clip diagnostic boxes to the
% visible figure area, while retaining the unmodified box in UserData.
leftValue = max(0, rawBox(1));
bottomValue = max(0, rawBox(2));
rightValue = min(figureSize(1), rawBox(1) + rawBox(3));
topValue = min(figureSize(2), rawBox(2) + rawBox(4));

displayBox = [ ...
    leftValue, ...
    bottomValue, ...
    max(0, rightValue - leftValue), ...
    max(0, topValue - bottomValue)];

if displayBox(3) <= 0 || displayBox(4) <= 0
    warning('getContentBox:AnnotationOutsideFigure', ...
        ['Measured box "%s" lies outside the visible figure. ' ...
         'Raw box: [%s] pixels.'], ...
        description, ...
        strtrim(sprintf('%.12g ', rawBox)));
    return;
end

annotationHandle = annotation( ...
    figHandle, ...
    'rectangle', ...
    [0.01, 0.01, 0.01, 0.01], ...
    'Color', lineColor, ...
    'LineStyle', lineStyle, ...
    'LineWidth', lineWidth, ...
    'Tag', debugTag);

annotationHandle.Units = 'pixels';
annotationHandle.Position = displayBox;
annotationHandle.UserData = struct( ...
    'description', description, ...
    'rawBox', reshape(double(rawBox), 1, 4), ...
    'displayBox', displayBox);

try
    annotationHandle.HitTest = 'off';
    annotationHandle.PickableParts = 'none';
catch
end

end


function figureSize = local_getFigureSizePx_(figHandle)
%LOCAL_GETFIGURESIZEPX_ Return the figure client area size in pixels.

figureSize = [nan, nan];

try
    figurePosition = reshape(double(getpixelposition(figHandle)), 1, 4);
    figureSize = figurePosition(3:4);
catch
    originalUnits = figHandle.Units;
    cleanupObj = onCleanup(@() ...
        local_restoreUnits_(figHandle, originalUnits));

    figHandle.Units = 'pixels';
    figurePosition = reshape(double(figHandle.Position), 1, 4);
    figureSize = figurePosition(3:4);
end

end

function local_deleteAnnotations_(figHandle, debugTag)
%LOCAL_DELETEANNOTATIONS_ Delete diagnostic rectangles created here.

debugHandles = findall(figHandle, 'Tag', debugTag);

if ~isempty(debugHandles)
    delete(debugHandles(isgraphics(debugHandles)));
end

end

function local_restoreUnits_(objectHandle, originalUnits)
%LOCAL_RESTOREUNITS_ Restore Units without masking an earlier exception.

if isgraphics(objectHandle)
    try
        objectHandle.Units = originalUnits;
    catch
    end
end

end

function tf = local_isValidBox_(box)
%LOCAL_ISVALIDBOX_ Validate a finite positive rectangle.

tf = ...
    isnumeric(box) && ...
    numel(box) == 4 && ...
    all(isfinite(box)) && ...
    box(3) > 0 && ...
    box(4) > 0;

end
