// =============================================================================
// PROJECT CHRONO - http://projectchrono.org
//
// Copyright (c) 2019 projectchrono.org
// All rights reserved.
//
// Use of this source code is governed by a BSD-style license that can be found
// in the LICENSE file at the top level of the distribution and at
// http://projectchrono.org/license-chrono.txt.
//
// =============================================================================
// Authors: Asher Elmquist
// =============================================================================
//
// camera ray launch kernels
//
// =============================================================================

#include "chrono_sensor/optix/shaders/device_utils.h"

extern "C" __global__ void __raygen__camera_pinhole() {
    const RaygenParameters* raygen = (RaygenParameters*)optixGetSbtDataPointer();
    const CameraParameters& camera = raygen->specific.camera;

    const uint3 idx = optixGetLaunchIndex();
    const uint3 screen = optixGetLaunchDimensions();
    const unsigned int image_index = screen.x * idx.y + idx.x;

    float2 d =
        (make_float2(idx.x, idx.y) + make_float2(0.5, 0.5)) / make_float2(screen.x, screen.y) * 2.f - make_float2(1.f);
    d.y *= (float)(screen.y) / (float)(screen.x);  // correct for the aspect ratio

    const float t_frac = 0;  // 0-1 between start and end time of the camera (chosen here)
    const float t_traverse = raygen->t0 + t_frac * (raygen->t1 - raygen->t0);  // simulation time when ray is sent
    float3 ray_origin = lerp(raygen->pos0, raygen->pos1, t_frac);
    float4 ray_quat = nlerp(raygen->rot0, raygen->rot1, t_frac);
    const float h_factor = camera.hFOV / CUDART_PI_F * 2.0;
    float3 forward;
    float3 left;
    float3 up;

    basis_from_quaternion(ray_quat, forward, left, up);
    float3 ray_direction = normalize(forward - d.x * left * h_factor + d.y * up * h_factor);

    PerRayData_camera prd = default_camera_prd();
    prd.use_gi = camera.use_gi;
    if (camera.use_gi) {
        prd.rng = camera.rng_buffer[image_index];  // sensor_rand(100 * (idx.y * screen.x + idx.x));
    }
    unsigned int opt1;
    unsigned int opt2;
    pointer_as_ints(&prd, opt1, opt2);

    optixTrace(params.root, ray_origin, ray_direction, params.scene_epsilon, 1e16f, t_traverse, OptixVisibilityMask(1),
               OPTIX_RAY_FLAG_NONE, CAMERA_RAY_TYPE, RAY_TYPE_COUNT, CAMERA_RAY_TYPE, opt1, opt2);

    camera.frame_buffer[image_index] = make_float4(prd.color.x, prd.color.y, prd.color.z, 1.f);
    if (camera.use_gi) {
        camera.albedo_buffer[image_index] = make_float4(prd.albedo.x, prd.albedo.y, prd.albedo.z, 0.f);
        float screen_n_x = -Dot(left, prd.normal);
        float screen_n_y = -Dot(up, prd.normal);
        camera.normal_buffer[image_index] = make_float4(screen_n_x, screen_n_y, 0.f, 0.f);
    }
}

/// Camera ray generation program using an FOV lens model
extern "C" __global__ void __raygen__camera_fov_lens() {
    const RaygenParameters* raygen = (RaygenParameters*)optixGetSbtDataPointer();
    const CameraParameters& camera = raygen->specific.camera;

    const uint3 idx = optixGetLaunchIndex();
    const uint3 screen = optixGetLaunchDimensions();
    const unsigned int image_index = screen.x * idx.y + idx.x;

    float2 d =
        (make_float2(idx.x, idx.y) + make_float2(0.5, 0.5)) / make_float2(screen.x, screen.y) * 2.f - make_float2(1.f);
    d.y *= (float)(screen.y) / (float)(screen.x);  // correct for the aspect ratio

    if (abs(d.x) > 1e-5 || abs(d.y) > 1e-5) {
        float r1 = sqrtf(d.x * d.x + d.y * d.y);
        float r2 = tanf(r1 * tanf(camera.hFOV / 2.0)) / tanf(camera.hFOV / 2.0);
        float scaled_extent = tanf(tanf(camera.hFOV / 2.0)) / tanf(camera.hFOV / 2.0);
        d.x = d.x * (r2 / r1) / scaled_extent;
        d.y = d.y * (r2 / r1) / scaled_extent;
    }

    const float t_frac = 0;  // 0-1 between start and end time of the camera (chosen here)
    const float t_traverse = raygen->t0 + t_frac * (raygen->t1 - raygen->t0);  // simulation time when ray is sent
    float3 ray_origin = lerp(raygen->pos0, raygen->pos1, t_frac);
    float4 ray_quat = nlerp(raygen->rot0, raygen->rot1, t_frac);
    const float h_factor = camera.hFOV / CUDART_PI_F * 2.0;
    float3 forward;
    float3 left;
    float3 up;

    basis_from_quaternion(ray_quat, forward, left, up);
    float3 ray_direction = normalize(forward - d.x * left * h_factor + d.y * up * h_factor);

    PerRayData_camera prd = default_camera_prd();
    prd.use_gi = camera.use_gi;
    if (camera.use_gi) {
        prd.rng = camera.rng_buffer[image_index];  // sensor_rand(100 * (idx.y * screen.x + idx.x));
    }
    unsigned int opt1;
    unsigned int opt2;
    pointer_as_ints(&prd, opt1, opt2);
    optixTrace(params.root, ray_origin, ray_direction, params.scene_epsilon, 1e16f, t_traverse, OptixVisibilityMask(1),
               OPTIX_RAY_FLAG_NONE, CAMERA_RAY_TYPE, RAY_TYPE_COUNT, CAMERA_RAY_TYPE, opt1, opt2);

    camera.frame_buffer[image_index] = make_float4(prd.color.x, prd.color.y, prd.color.z, 1.f);
    if (camera.use_gi) {
        camera.albedo_buffer[image_index] = make_float4(prd.albedo.x, prd.albedo.y, prd.albedo.z, 0.f);
        float screen_n_x = -Dot(left, prd.normal);
        float screen_n_y = -Dot(up, prd.normal);
        camera.normal_buffer[image_index] = make_float4(screen_n_x, screen_n_y, 0.f, 0.f);
    }
}