function [p, legacy] = binPath(blockPath, storeName, location)
%BINPATH  Where the exported binary of a TDT block should live.
%
%   [p, legacy] = mu.binPath(blockPath, storeName, location)
%
%   The historical exporters wrote <store>.bin straight into the raw block
%   folder (<tank>\Block-N\Wave.bin). That violates the project rule "raw data
%   is read-only": an export could overwrite or clutter the acquisition folder,
%   and a half-written file sits next to the original recording.
%
%   New convention (2026-11-01):
%       <tank>\BIN\<Block-N>_<store>.bin
%   i.e. one BIN folder per tank, one file per block, next to (not inside) the
%   raw blocks.
%
%   Inputs
%     blockPath : '<...>\<tank>\Block-N'
%     storeName : stream/store name, default 'Wave'
%     location  : "BIN"    -> new convention (default)
%                 "BLOCK"  -> legacy location, for reading old exports
%                 <folder> -> explicit folder
%
%   Outputs
%     p      : path to use for writing
%     legacy : the old in-block path (use it to detect already exported files)

if nargin < 2 || isempty(storeName), storeName = 'Wave'; end
if nargin < 3 || isempty(location), location = "BIN"; end

blockPath = char(blockPath);
blockName = regexp(blockPath, 'Block-\d+', 'match', 'once');
if isempty(blockName)
    error('mu:binPath:badBlockPath', ...
        'Cannot find a "Block-N" component in %s', blockPath);
end
tankPath = erase(blockPath, blockName);

legacy = fullfile(blockPath, [storeName '.bin']);

if isstring(location) || ischar(location)
    switch upper(string(location))
        case "BIN"
            p = fullfile(tankPath, 'BIN', sprintf('%s_%s.bin', blockName, storeName));
            return
        case "BLOCK"
            p = legacy;
            return
        otherwise
            % treated as an explicit folder below
            location = char(location);
    end
end

p = fullfile(location, sprintf('%s_%s.bin', blockName, storeName));
end
