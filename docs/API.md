# LuauUI — preview reference

## Project layout
- A project is a folder with a `ui/` subfolder (or `src/ui/`, or `"uiDir"` in `luauui.json`).
- Every `ui/**/*.luau` (or `.lua`) file is one UI in the rack, named by its path without the extension (`Shop`, `menus/Settings`).
- Files and folders whose names start with `_` are shared modules, not UIs (for example `ui/_shared/Theme.luau`, `ui/_components/Button.luau`).
- Each file runs in its own fresh Luau VM. Saving any file re-renders it right away (hot reload). If a shared module changes, every UI is re-rendered.

## What a UI module returns
1. **A function component**: `return function(props) return e("ScreenGui", ...) end`
2. **An element**: `return LuauUI.createElement("ScreenGui", ...)`
3. **An Instance**: build with `Instance.new(...)` and `return gui` (a ScreenGui or a Frame).
4. **Nothing**: anything parented to `Players.LocalPlayer.PlayerGui` or `StarterGui` is shown, and so is anything mounted with `Roact.mount(tree, playerGui)` / `ReactRoblox.createRoot(x):render(tree)`.
5. **A story table**: `return { story = Component, props = {...} }` (also `render`, `Component` or `App`).

A root that is not a ScreenGui is wrapped in an implicit ScreenGui (IgnoreGuiInset = false).

## LuauUI (React / Roact compatible)
`require(Packages.LuauUI)`, `require(Packages.React)`, `require(Packages.Roact)`, `require(game.ReplicatedStorage.Packages.React)`, and the globals `LuauUI` / `React` / `Roact` all return the same library:
- `createElement(class|component, props, children)`. Children are a keyed table (key = Name), an array, or varargs.
- `Event.Activated`, `Event.MouseButton1Click`, `Event.MouseEnter`, `Event.MouseLeave`, `Event.FocusLost`, …, and `Change.Text`
- `Children`, `Ref`, `None`, `Fragment`, `createFragment`, `createRef`, `forwardRef`, `memo`
- Hooks: `useState`, `useReducer`, `useEffect`, `useLayoutEffect`, `useMemo`, `useCallback`, `useRef`, `useContext`, `useBinding`, `useId`
- `createContext` (Provider / Consumer), `createBinding`, `joinBindings`, `binding:map()`
- Class components: `Component:extend("Name")`, with `init`, `render`, `setState`, `didMount`, `willUnmount`, `defaultProps`
- `mount` / `update` / `unmount`, `createRoot`, `createPortal`
- React-lua style event props also work: `onActivated = fn`

## Emulated Roblox API
- Datatypes: `UDim`, `UDim2` (`new`, `fromScale`, `fromOffset`, `Lerp`, `+`, `-`), `Vector2`, `Vector3`, `Color3` (`new`, `fromRGB`, `fromHex`, `fromHSV`, `Lerp`, `ToHex`, `ToHSV`), `ColorSequence(+Keypoint)`, `NumberSequence(+Keypoint)`, `NumberRange`, `Rect`, `TweenInfo`, `Font` (`new`, `fromName`, `fromEnum`), `Enum.*` (any name), `typeof`
- `Instance.new(class)`: properties, `.Parent`, `Name`, child access with `inst.Child`, `FindFirstChild(name, recursive)`, `WaitForChild`, `FindFirstChildOfClass` / `WhichIsA`, `GetChildren`, `GetDescendants`, `IsA`, `Destroy`, `ClearAllChildren`, `Clone`, attributes, `GetPropertyChangedSignal`, signals (`Activated:Connect`, `MouseEnter`, `FocusLost`, `Changed`, …), and `TweenSize` / `TweenPosition`, which apply the end value immediately
- `game:GetService(...)`: `Players` (LocalPlayer, PlayerGui), `StarterGui`, `TweenService` (`:Create():Play()` applies the goals immediately), `RunService`, `UserInputService` (TouchEnabled follows the device), `GuiService` (inset 58), `HttpService` (`JSONEncode` / `JSONDecode` / `GenerateGUID`), `MarketplaceService` (stubs, nothing is bought), `TextService`, `Workspace.CurrentCamera.ViewportSize`, and others as stubs
- `task.spawn` / `defer` run immediately. `task.wait` / `wait` / `:Wait()` stop that thread (the preview shows a single frame). `task.delay` does not run.
- `print` / `warn` appear in the app console and in MCP results.

## require
- `require(script.Parent.Theme)`, `require(script.Parent._shared.Theme)`: path relative to the file
- `require("./Button")`, `require("../_shared/Theme")`, `require("@self/Child")`, `require("@project/ui/_shared/Theme")`
- `require(game.ReplicatedStorage.X.Y)`: looked up in `<project>/ReplicatedStorage/X/Y`, `<project>/X/Y`, `<project>/src/X/Y`, `<project>/src/shared/X/Y` and `<project>/ui/X/Y`. A file can be `Y.luau`, `Y.lua` or `Y/init.luau`.

## Rendered classes and properties
- ScreenGui (Enabled, IgnoreGuiInset, DisplayOrder), Frame, TextLabel, TextButton, TextBox, ImageLabel, ImageButton, ScrollingFrame (CanvasSize, AutomaticCanvasSize), CanvasGroup (GroupTransparency), and Folder (its children are drawn)
- Size, Position, AnchorPoint, Rotation, ZIndex, Visible, AutomaticSize, ClipsDescendants, BackgroundColor3, BackgroundTransparency, BorderSizePixel, BorderColor3, BorderMode, LayoutOrder
- Text: Text, TextColor3, TextTransparency, TextSize, TextScaled, TextWrapped, TextXAlignment, TextYAlignment, Font or FontFace (Gotham/Montserrat, SourceSans, Builder, Fredoka, LuckiestGuy, Bangers, Roboto, Arial and more, mapped to Google Fonts), RichText (b, i, u, s, font color/size/face/weight, br), TextStrokeTransparency, TextStrokeColor3, LineHeight, TextTruncate, and on TextBox: PlaceholderText, PlaceholderColor3, MultiLine, TextEditable
- Image: `rbxassetid://ID`, fetched from the Roblox thumbnails API and cached in `%LOCALAPPDATA%/LuauUI/cache`. A relative path such as `assets/coin.png` is read from the project folder. Also ScaleType (Stretch, Fit, Crop, Tile, Slice with SliceCenter / SliceScale), ImageColor3, ImageTransparency
- Modifiers: UICorner (scale is taken from the smaller side), UIStroke (Border or Contextual text stroke), UIGradient (Color, Transparency, Rotation, Offset, applied to the background, or to the text when the background is transparent), UIPadding, UIListLayout (FillDirection, Padding, alignments, SortOrder, Wraps), UIGridLayout (CellSize, CellPadding), UIAspectRatioConstraint, UISizeConstraint, UITextSizeConstraint, UIScale
- Buttons darken on hover and press when AutoButtonColor is true.

## Limits
- One frame of time: tweens and delays jump to their end value, and Heartbeat / RenderStepped never fire.
- 3D objects, ViewportFrame content, BillboardGui / SurfaceGui placement in the world, and sounds are not simulated.
- A run that lasts longer than 2 s is stopped (to catch infinite loops).

## Devices
desktop 1920×1080, laptop 1366×768, tablet 1024×768, phone 844×390, phone-portrait 390×844, console 1920×1080. The Roblox top bar takes 58 px unless the ScreenGui sets `IgnoreGuiInset = true`.
