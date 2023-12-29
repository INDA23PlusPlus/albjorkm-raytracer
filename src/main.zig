const std = @import("std");

const noise3D = @import("./noise.zig").noise3D;

const Vec3 = @Vector(3, f64);

fn normVec3(a: Vec3) Vec3 {
    const len = @sqrt(@reduce(.Add, (a*a)));
    return a / @as(Vec3, @splat(len));
}

fn dotVec3(a: Vec3, b: Vec3) f64 {
    return @reduce(.Add, (a*b));
}


const Color = @Vector(4, f64);

const GraphicalSphere = struct {
    pos: Vec3,
    radius: f64,
    color: Color,
};

const GraphicalPlane = struct {
    norm: Vec3,
    pos: Vec3,
};

const GraphicalPrimitive = union(enum) {
    sphere: GraphicalSphere,
    plane: GraphicalPlane,
};

const Light = struct {
    pos: Vec3,
};

const Scene = struct {
    graphics: []GraphicalPrimitive,
    lights: []Light
};

const no_intersect = std.math.inf(f64);

fn intersectPlane(origin: Vec3, direction: Vec3, object: GraphicalPlane) f64 {
    const denom = dotVec3(object.norm, direction);
    if (denom > 0.000001) {
        const diff = object.pos - origin;
        const distance = dotVec3(diff, object.norm) / denom;
        if (distance >= 0) {
            return distance;
        }
    }
    return no_intersect;
}

fn intersectSphere(origin: Vec3, direction: Vec3, object: GraphicalSphere) f64 {
    // https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
    const L = object.pos - origin;
    const tca = dotVec3(L, direction);
    const d2 = dotVec3(L, L) - tca * tca;
    const radius2 = object.radius * object.radius;
    if (d2 > radius2) {
        return no_intersect;
    }
    const thc = @sqrt(radius2 - d2);
    const t0 = tca - thc;
    const t1 = tca + thc;
    if (t0 > 0.001) {
        return t0;
    }
    if (t1 > 0.001) {
        return t1;
    }
    return no_intersect;
}

const RaycastResult = struct {
    distance: f64,
    color: Color,
};

fn raycast_primitives(origin: Vec3, direction: Vec3, primitives: []const GraphicalPrimitive) RaycastResult {
    var result = RaycastResult {
        .distance = no_intersect,
        .color = Color { 1, 1, 1, 1 },
    };
    for (primitives) |object| {
        switch (object) {
            .sphere => |s| {
                const dist = intersectSphere(origin, direction, s);
                if (dist < result.distance) {
                    result.distance = dist;
                    result.color = s.color;
                }
            },
            .plane => |p| {
                const dist = intersectPlane(origin, direction, p);
                if (dist < result.distance) {
                    const vec3_distance: Vec3 = @splat(dist);
                    const intersect_point = origin + vec3_distance * direction;

                    result.distance = dist;

                    if (dist > 100) {
                        result.color = Color {0, 0.5, 0, 1};
                        continue;
                    }
                    const n = noise3D(f64, intersect_point[0], intersect_point[1], intersect_point[2]);
                    const n2 = noise3D(f64, intersect_point[0] + 1000, intersect_point[1], intersect_point[2]);
                    const n3 = noise3D(f64, intersect_point[0] * 16, intersect_point[1] * 16, intersect_point[2] * 16);
                    const n4 = noise3D(f64, intersect_point[0] * 48, intersect_point[1] * 48, intersect_point[2] * 8);

                    if (n4 > 0.3) {
                        result.color = Color {0.2, 0.7, 0, 1};
                    } else if (n3 > 0.4) {
                        result.color = Color {0.2, 0.5, 0, 1};
                    } else if (n > 0.3) {
                        result.color = Color {0.1, 0.65, 0, 1};
                    } else if (dist < 10 and n2 > 0.3) {
                        result.color = Color {0, 0.6, 0, 1};
                    } else {
                        result.color = Color {0, 0.5, 0, 1};
                    }
                }
            },
        }
    }

    if (result.distance < no_intersect) {
        return result;
    }

    // Hit the skybox.
    result.color = Color { 0.2, 0.2, (1 - dotVec3(direction, Vec3{0,1,0})), 1};
    return result;
}

fn render(width: usize, height: usize, input: *const Scene, output: []Color) void {
    const fov: f64 = 1.05;
    const tanFOV = 2 * @tan(fov / 2);
    const floatHeight: f64 = @floatFromInt(height);
    const widthDiv2 = @as(f64, @floatFromInt(width)) / 2;
    const heightDiv2: f64 = floatHeight / 2;
    for (0..width*height) |pixel| {
        const i: f64 = @floatFromInt(pixel % width);
        const j: f64 = @floatFromInt(pixel / height);
        const x = (i + 0.5) - widthDiv2;
        const y = -(j + 0.5) + heightDiv2;
        const z = -floatHeight / tanFOV;
        const direction = normVec3(Vec3{x, y, z});

        const cast_result = raycast_primitives(Vec3{0,0,0}, direction, input.graphics);

        var in_light = false;
        if (cast_result.distance < no_intersect) {
            const vec3_distance: Vec3 = @splat(cast_result.distance);
            const intersect_point = Vec3{0,0,0} + vec3_distance * direction;
            for(input.lights) |light| {
                const new_direction = normVec3(light.pos - intersect_point);
                const light_cast = raycast_primitives(intersect_point, new_direction, input.graphics);
                if (light_cast.distance == no_intersect) {
                    in_light = true;
                    break;
                }
            }
        } else {
            in_light = true;
        }
        if (in_light) {
            output[pixel] = cast_result.color;
        } else {
            output[pixel] = cast_result.color / Color {2, 2, 2, 1};
        }
    }
}

pub fn main() !void {
    const width = 1024;
    const height = 768;
    var fb = try std.heap.page_allocator.alloc(Color, width*height);

    const flowers = [_]GraphicalPrimitive{
        .{
            .sphere = .{
                .pos = Vec3{0, 0, 0},
                .radius = 0.05,
                .color = Color{0.9, 0.1, 0.1, 1},
            }
        }
    } ** 64;

    var input_spheres = flowers ++ [_]GraphicalPrimitive{
        .{
            .sphere = .{
                .pos = Vec3{-10, 0, -17},
                .radius = 2.2,
                .color = Color{0.5, 0.7, 0.3, 1},
            }
        },
         .{
            .sphere = .{
                .pos = Vec3{-2, 1, -10},
                .radius = 2,
                .color = Color{0.9, 0.9, 0.5, 1},
            }
        },
        .{
            .sphere = .{
                .pos = Vec3{-2, 7.5, -10},
                .radius = 3,
                .color = Color{0.9, 0.9, 0.5, 1},
            }
        },

        .{
            .sphere = .{
                .pos = Vec3{8, 5.3, -20},
                .radius = 4,
                .color = Color{0.2, 0.5, 0.3, 1},
            }
        },
        .{
            .plane = .{
                .norm = Vec3{0, -1, 0},
                .pos = Vec3{0, -1, 0},
            }
        },

    };

    var randSeeded = std.rand.DefaultPrng.init(333);
    const rand = randSeeded.random();
    for (input_spheres[0..64]) |*flower| {
        flower.sphere.pos = Vec3{(rand.float(f64) - 0.6) * 30, -1, (rand.float(f64) - 1) * 30};
    }

    var lights = [_]Light {
        .{
            .pos = Vec3{0, 20, 0},
        }
    };

    const scene = Scene {
        .graphics = &input_spheres,
        .lights = &lights,
    };

    render(width, height, &scene, fb);


    var output = std.ArrayList(u8).init(std.heap.page_allocator);
    var writer = output.writer();
    try writer.print("P6\n{d} {d}\n255\n", .{width, height});
    for (fb) |pixel| {
        try writer.writeByte(@intFromFloat(255 * @max(0, @min(1, pixel[0]))));
        try writer.writeByte(@intFromFloat(255 * @max(0, @min(1, pixel[1]))));
        try writer.writeByte(@intFromFloat(255 * @max(0, @min(1, pixel[2]))));
    }

    try std.fs.cwd().writeFile("./out.ppm", output.items);
}

