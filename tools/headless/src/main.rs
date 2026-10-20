// Tiny Luau host for headless checks: `headless <script.luau> [args...]`.
// Exposes readfile(path), compile(source, chunkname) and ARGS to the script.
use mlua::prelude::*;
fn main() -> LuaResult<()> {
    let lua = Lua::new();
    let g = lua.globals();
    g.set("readfile", lua.create_function(|_, p: String| Ok(std::fs::read_to_string(&p).map_err(|e| LuaError::external(format!("{p}: {e}")))?))?)?;
    g.set("compile", lua.create_function(|l, (src, name): (String, String)| l.load(src).set_name(name).into_function())?)?;
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("usage: headless <script.luau> [args...]");
    g.set("ARGS", args.collect::<Vec<String>>())?;
    let src = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
    lua.load(src).set_name(path).exec()
}
