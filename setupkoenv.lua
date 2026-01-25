-- Set search path for `require()`.
-- Local ffi/ directory first, then KOReader paths as fallback
local basedir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
package.path =
	basedir .. "?.lua;" ..
	basedir .. "ffi/?.lua;" ..
	"common/?.lua;frontend/?.lua;" ..
	package.path
package.cpath =
	basedir .. "libs/?.so;" ..
	"common/?.so;/usr/lib/lua/?.so;" ..
	package.cpath
