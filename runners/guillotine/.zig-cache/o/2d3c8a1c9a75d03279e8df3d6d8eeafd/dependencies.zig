pub const packages = struct {
    pub const @"1220cee254c73272258d81cf679bffb0d4ecc3be6f0263b5a724fe969a9566802020" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/zbench-0.10.0-YTdc714iAQDO4lTHMnIljYHPZ5v_sNTsw75vAmO1pyT-";
        pub const build_zig = @import("1220cee254c73272258d81cf679bffb0d4ecc3be6f0263b5a724fe969a9566802020");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"Guillotine-0.0.0-VmyYdDbNKADqbMCLAM8GYba_qFGxR2vMd-YJmWwpJAzH" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/Guillotine-0.0.0-VmyYdDbNKADqbMCLAM8GYba_qFGxR2vMd-YJmWwpJAzH";
        pub const build_zig = @import("Guillotine-0.0.0-VmyYdDbNKADqbMCLAM8GYba_qFGxR2vMd-YJmWwpJAzH");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "webui", "webui-2.5.0-beta.4-pxqD5esSNwCHzwq6ndnW-ShzC_nPNAzGu13l4Unk0rFl" },
            .{ "c_kzg_4844", "c_kzg_4844-0.0.0-UbJ7acpiHQBNlbFymCuO9OTLut3UtdHz4OiDZBc5pCAd" },
            .{ "zbench", "1220cee254c73272258d81cf679bffb0d4ecc3be6f0263b5a724fe969a9566802020" },
        };
    };
    pub const @"c_kzg_4844-0.0.0-UbJ7acpiHQBNlbFymCuO9OTLut3UtdHz4OiDZBc5pCAd" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/c_kzg_4844-0.0.0-UbJ7acpiHQBNlbFymCuO9OTLut3UtdHz4OiDZBc5pCAd";
        pub const build_zig = @import("c_kzg_4844-0.0.0-UbJ7acpiHQBNlbFymCuO9OTLut3UtdHz4OiDZBc5pCAd");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"webui-2.5.0-beta.4-pxqD5esSNwCHzwq6ndnW-ShzC_nPNAzGu13l4Unk0rFl" = struct {
        pub const build_root = "/Users/williamcory/.cache/zig/p/webui-2.5.0-beta.4-pxqD5esSNwCHzwq6ndnW-ShzC_nPNAzGu13l4Unk0rFl";
        pub const build_zig = @import("webui-2.5.0-beta.4-pxqD5esSNwCHzwq6ndnW-ShzC_nPNAzGu13l4Unk0rFl");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "Guillotine", "Guillotine-0.0.0-VmyYdDbNKADqbMCLAM8GYba_qFGxR2vMd-YJmWwpJAzH" },
};
