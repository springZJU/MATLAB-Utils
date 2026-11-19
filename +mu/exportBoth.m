function out = exportBoth(fig, base, varargin)
%EXPORTBOTH  Export a figure to PDF (mm-exact) and to a raster format.
%
%   out = mu.exportBoth(fig, base)
%   out = mu.exportBoth(fig, base, "Formats", ["pdf","jpg"], "Resolution", 300)
%
%   base is a path WITHOUT extension; the extension is chosen per format.
%   The PDF is produced by mu.exportFigure2PDF so its size is specified in
%   millimetres and is reproducible across machines; the raster copy keeps
%   the existing review/archive workflow (JPG by default).
%
%   INPUTS
%     fig   - scalar figure handle
%     base  - char/string output path without extension
%
%   NAME-VALUE
%     Formats    - string array, default ["pdf","jpg"]
%                  allowed: "pdf", "jpg", "png", "fig"
%     Resolution - raster DPI, default 300
%     WidthMm    - PDF width in mm, default: figure width converted to mm
%     HeightMm   - PDF height in mm, default: figure height converted to mm
%
%   OUTPUT
%     out - struct with one field per written file (.pdf/.jpg/...), each
%           holding the full path.
%
%   See also mu.exportFigure2PDF, mu.getContentBox.

mIp = inputParser;
mIp.addRequired("fig", @(x) isgraphics(x, "figure") && isscalar(x));
mIp.addRequired("base", @(x) ischar(x) || (isstring(x) && isscalar(x)));
mIp.addParameter("Formats", ["pdf", "jpg"], @(x) isstring(x) || iscellstr(x));
mIp.addParameter("Resolution", 300, @(x) isnumeric(x) && isscalar(x) && x > 0);
mIp.addParameter("WidthMm", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
mIp.addParameter("HeightMm", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
mIp.parse(fig, base, varargin{:})

base = char(base);
% Accept a path that already carries an extension: mu.exportBoth(fig,
% "fig.png", "Formats","pdf") writes fig.pdf next to it, which lets the
% existing exportgraphics line stay untouched.
[baseDir, stem, ext] = fileparts(base);
if any(strcmpi(ext, {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ...
        ".pdf", ".fig", ".eps"}))
    base = fullfile(baseDir, stem);
end
formats = lower(string(mIp.Results.Formats));
dpi = mIp.Results.Resolution;

% On-screen size -> millimetres. This is the size the figure currently shows,
% so the PDF matches what was reviewed instead of a hard-coded default.
ppi = get(groot, "ScreenPixelsPerInch");
if isempty(ppi) || ~isfinite(ppi) || ppi <= 0, ppi = 96; end
wMm = mIp.Results.WidthMm;
hMm = mIp.Results.HeightMm;
if isempty(wMm), wMm = fig.Position(3) / ppi * 25.4; end
if isempty(hMm), hMm = fig.Position(4) / ppi * 25.4; end

out = struct();
for f = formats(:)'
    switch f
        case "pdf"
            % exportFigure2PDF writes the file and returns nothing.
            mu.exportFigure2PDF(fig, base, wMm, hMm);
            out.pdf = sprintf("%s.pdf", base);
        case {"jpg", "png"}
            % exportgraphics writes the file and returns nothing.
            exportgraphics(fig, sprintf("%s.%s", base, f), "Resolution", dpi);
            out.(f) = sprintf("%s.%s", base, f);
        case "fig"
            out.fig = sprintf("%s.fig", base);
            savefig(fig, out.fig);
        otherwise
            error("mu:exportBoth:badFormat", "Unsupported format: %s", f);
    end
end
end
