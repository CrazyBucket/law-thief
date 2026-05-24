# 演示素材速查（Doodle RPG + VFX Free Pack）

本页用于做 **prototype / demo** 时快速知道「素材在哪儿、怎么用、署名注意什么」。工程中已接入的方式见下文「在本仓库里的落点」。

---

## 本仓库里的落点

| 素材包 | 本地原始位置（默认下载目录） | 工程内用法 |
|---|---|---|
| **Doodle RPG** | `~/Downloads/Doodle RPG.zip`（源压缩包仍可留在此处） | 已解压到 `assets/demo/doodle-rpg/`（可直接用 `res://` 引用） |
| **VFX Free Pack** | `~/Downloads/VFX Free Pack/`（以及同目录压缩包） | **推荐本机 symlink**，使 Godot FileSystem 下也能看到：`assets/demo/vfx-free-pack/` → `~/Downloads/VFX Free Pack`。该路径已写入 `.gitignore`，不会进版本库 |

若你换新机器或重下素材，可把「下载路径」换掉后重建 symlink（在**仓库根目录**执行）：

```bash
mkdir -p assets/demo
ln -sfn ~/Downloads/VFX\ Free\ Pack assets/demo/vfx-free-pack
```
---

## Doodle RPG（手绘风 RPG 精灵/UI/字体）

- **解压后根目录**：`assets/demo/doodle-rpg/`  
- **主要资源**：`assets/demo/doodle-rpg/ALL SPRITES/`  
- **许可证**：同级 `LICENSE.txt`（允许商用/改版；禁止转卖、禁止伪称原创；署名受作者欢迎）

### 当前战斗 / UI 实际用到的 Knight 文件

| 用途 | `res://` 路径 |
|---|---|
| 行走 / 待机 / 朝向帧 | `.../Knight/Walking w Sword/` 下 `Forward`、`Up`、`Left`、`Right`、`DL`、`DR`、`UL`、`UR` + `0/1/2.png` |
| 近战劈砍帧 | `.../Knight/Sword Swing/` 同上朝向 + `0/1/2.png` |
| 脚底椭圆阴影 | `.../Knight/Shadow.png` |
| 侧栏与名单小头像 | 与待机一致：`Walking w Sword/Forward0.png`（逻辑在 `UnitLooks` → `doodle_unit_sprites.gd`） |

**为何曾出现「无法加载」**：`.gitignore` 忽略所有 `*.import`，新克隆或清空 `.godot/` 时，Godot 尚未把 PNG 导入成 `.ctex`，纯 `load()` 会失败。运行时代码已走 **`ResourceLoader.load` → 失败则 `Image.load` 直读 PNG** 的回退，不应再刷屏 WARNING（源文件必须在上述路径存在）。

### 顶层结构（节选）

根目录下设 `Environment Grid*.png`、`Extras.png`、`Tiles`、`Knight`、`UI`、`Fonts`、`Pickups and Items`、`Particles`、`Debris` 等。**对齐格子**时请优先对照 `Environment Grid Size Ref.png` 与同名网格图。

简要目录用途：

| 路径 | 适合 demo 的点 |
|---|---|
| `ALL SPRITES/Knight/` | 主角全套动作（普攻/攀爬/推拉/翻滚/持物等）；子目录里是序列帧 PNG |
| `ALL SPRITES/Tiles/` | 地块与场景拼接 |
| `ALL SPRITES/Pickups and Items/` | 道具与可拾取物图标 |
| `ALL SPRITES/UI/` | HUD、菜单、光标、分段转场等大图序列 |
| `ALL SPRITES/Fonts/*.ttf` | 手写/涂鸦字形，可直接在项目设置里加到「主题 / 控件字体」 |

### Godot（4.x）里最省事的用法

1. 在场景中拖入 `Sprite2D`，`Texture` 指向单个 PNG（适合静态或非序列 UI）。  
2. 要走动画：序列帧可走 `AnimatedSprite2D` + `SpriteFrames`（或用 `AnimationPlayer` 轮换 `Sprite2D.texture`）。  
3. `.ttf`：在控件或全局主题里设为 `DynamicFont`。  
4. 若你发现边缘发糊：**先**在 Inspector 针对贴图试一下 `CanvasItem` → `Texture` 的滤波/缩放模式（按需「像素风格关滤波」）。

---

## VFX Free Pack（2D VFX）

- **本机解压目录**：`~/Downloads/VFX Free Pack`（工程中通过 `assets/demo/vfx-free-pack` symlink 对齐）  
- **体积**：约百兆量级；不建议直接整包提交 Git，以保持仓库轻量。  
- **许可说明**：解压根目录未发现独立 `LICENSE` 文本；对外发布或商业化 demo **务必回到你当初的下载页面**核对许可条款与是否需要署名。（把来源链接记在 PR 描述或 itch 存档里是个好习惯。）

### 编排方式（每个特效一套）

每组 `Effect_*` 下通常均有：

```
Effect_FooBar/
├── 60fps/{Frames,Spritesheets,Gifs}
└── 30fps/{Frames,Spritesheets,Gifs}
```

| 子目录 | 典型用途 |
|---|---|
| `Frames/` | **逐帧 PNG**，适合塞进 `AnimatedSprite2D / SpriteFrames` 或 Timeline |
| `Spritesheets/` | 单张图条带序列（示例命名：`Effect_BigHit_1_516x528.png`），适合 `AtlasTexture`/自写 UV 偏移，或由工具切成帧 |
| `Gifs/` | 快速目测节奏与色相；一般不直接跑进游戏运行时 |

仓库内当前包含的顶层特效文件夹（节选，完整列表请在 FileSystem 里展开）：  
`Effect_Anima`、`Effect_BigHit`、`Effect_BloodImpact`、`Effect_Charged`、`Effect_Constellation`、`Effect_DitheredFire`、`Effect_EldenRing`、`Effect_ElectricShield`、`Effect_Explosion`、`Effect_Explosion2`、`Effect_FastPixelFire`、`Effect_Hyperspeed`、`Effect_Impact`、`Effect_Kabooms`、`Effect_Magma`、`Effect_PowerChords`、`Effect_PuffAndStars`、`Effect_SmallHit`、`Effect_Tentacles`、`Effect_TheVortex`、`Effect_Wheel`、`Effect_Worm` 等。

### Godot 里做爆炸/击中闪一下的常见路径

1. **逐帧**：用 `Spritesheet` → 外部切成竖条/格子后导入为 `AtlasTexture`，或直接使用 `Frames` 里的序列。  
2. **挂载点**：棋盘格 UI 上可以叠 `CanvasLayer`/`SubViewport`，避免与等距格子坐标搅在一起（依你 demo 的镜头而定）。

### 与本战斗工程的对接（`isometric_board`）

当 `assets/demo/vfx-free-pack/` 可被 Godot 打开（本机 symlink 正常）且对应目录存在时，棋盘上的 **特效会优先使用该包**，扫描逻辑在 **`scripts/ui/vfx_pack_frames.gd`**（惰性缓存 `Frames` 下首个变体的全部 `.png`，按文件名排序）。

| 事件 | VFX Pack 文件夹 |
|---|---|
| `play_explosion` | `Effect_Explosion` |
| `play_damage_effect` | `Effect_SmallHit` |
| `play_poison_burst` | `Effect_PuffAndStars`（缺则用 Doodle `Puff_*`） |
| `play_heal_effect` | `Effect_Charged` |
| `play_gem_flash` | `Effect_PowerChords`（缺则用手绘菱形粒子） |

包不可用时沿用原有程序化粒子 / Doodle 回退，克隆仓库无 symlink 仍可跑 CI。

---

## 做 demo 时的一条龙检查清单（复制即用）

1. Godot FileSystem 能展开 `res://assets/demo/doodle-rpg/ALL SPRITES/`。  
2. `res://assets/demo/vfx-free-pack/` 若没有：按上文 `ln -sfn` 重建 symlink。  
3. 任一对外录屏/demo：画面角落或致谢里写明 **Doodle RPG 作者致谢**（许可鼓励）；VFX **按原始下载页为准**。  
4. 真要进主发布目录前：决定是否把 symlink 改成「复制进仓库子目录」（会增大体积）或继续做本机独占。
