shader_type canvas_item;

// 可调参数
uniform float blend_intensity : hint_range(0.0, 2.0) = 1.2; // 融合强度：觉得淡就往 1.0 以上拉，现在默认已提高到 1.2
uniform float grid_contrast : hint_range(0.5, 3.0) = 2.0;   // 棋盘自身对比度：越高格子越明显，默认提升至 2.0
uniform vec4 tint_color : source_color = vec4(0.15, 0.25, 0.2, 1.0); // 氛围调色：推荐用比草地深的暗绿色

// 获取背后的草地原图
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
    vec4 grid_texture = texture(TEXTURE, UV);
    
    // 1. 过滤素材的纯白背景
    if (grid_texture.r > 0.95 && grid_texture.g > 0.95 && grid_texture.b > 0.95) {
        discard;
    }
    
    // 2. 获取当前位置底部的草地原色
    vec3 screen_rgb = texture(screen_texture, SCREEN_UV).rgb;
    
    // 3. 提取棋盘纹理并增强对比度，让格子细节更硬朗、更清晰
    float luminance = dot(grid_texture.rgb, vec3(0.299, 0.587, 0.114));
    float contrast_luminance = pow(luminance, grid_contrast);
    vec3 grid_target_color = vec3(contrast_luminance) * tint_color.rgb;
    
    // 4. 【核心】经典高级的“叠加（Overlay）”算法
    // 它能让亮的更亮、暗的更暗，完美保留草地纹理的同时，强行压制住背景原有的格子
    vec3 blended_rgb;
    for(int i = 0; i < 3; i++) {
        if (screen_rgb[i] < 0.5) {
            blended_rgb[i] = 2.0 * screen_rgb[i] * grid_target_color[i];
        } else {
            blended_rgb[i] = 1.0 - 2.0 * (1.0 - screen_rgb[i]) * (1.0 - grid_target_color[i]);
        }
    }
    
    // 5. 已去掉边缘羽化，仅用棋盘自身的 Alpha 控制透明度
    float alpha_mask = grid_texture.a;
    
    // 6. 输出最终颜色（允许 blend_intensity 突破 1.0 以极大地增强清晰度）
    vec3 final_rgb = mix(screen_rgb, blended_rgb, clamp(blend_intensity * alpha_mask, 0.0, 1.0));
    COLOR = vec4(final_rgb, 1.0);
}