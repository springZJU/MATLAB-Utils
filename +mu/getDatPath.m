function p = getDatPath(s)
%GETDATPATH  Raw-data path of one Excel row / metadata struct, with fallbacks.
%
%   p = mu.getDatPath(s)
%
%   Why this exists (PHASE4_CHANGE_LIST.md P1-2):
%   The SPR tables (18 columns) carry a 'datPath' field; the GFJ tables
%   (38 columns) do not, and reading params.datPath there raised
%   "Unrecognized field name 'datPath'". The two formats drifted apart, so the
%   access is now centralised here.
%
%   Resolution order: datPath -> dataPath -> soundPath.
%   Returns a char row vector (or cellstr if the input field is a cell).

names = {'datPath', 'dataPath', 'soundPath'};
p = [];
for k = 1:numel(names)
    if isfield(s, names{k})
        v = s.(names{k});
        if ~isempty(v) && ~(ischar(v) && all(isspace(v))) && ~(isstring(v) && all(strlength(v) == 0))
            p = v;
            if k > 1
                warning('mu:getDatPath:fallback', ...
                    'Field "%s" is missing; using "%s" instead (GFJ 38-column format?).', ...
                    names{1}, names{k});
            end
            return
        end
    end
end

if isempty(p)
    error('mu:getDatPath:missing', ...
        ['No datPath/dataPath/soundPath found in this record. ', ...
         'This Excel is probably the GFJ 38-column format, which has no datPath column.']);
end
end
