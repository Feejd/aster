// KWin stawia każde nowe okno na środku ekranu, więc drugie okno programu przykrywałoby pierwsze co do piksela
// i wyglądałoby tak, jakby nic się nie otworzyło. Takie okno przesuwamy schodkowo.
"use strict";

const Step = 32;

function taken(window, x, y) {
    return workspace.windowList().some(other => other !== window && other.normalWindow && !other.minimized
        && Math.abs(other.frameGeometry.x - x) < 8 && Math.abs(other.frameGeometry.y - y) < 8);
}

workspace.windowAdded.connect(window => {
    if (!window.normalWindow || window.fullScreen)
        return;
    const area = workspace.clientArea(KWin.PlacementArea, window);
    const g = window.frameGeometry;
    let x = g.x, y = g.y;
    while (taken(window, x, y) && x + g.width + Step <= area.x + area.width && y + g.height + Step <= area.y + area.height) {
        x += Step;
        y += Step;
    }
    if (x !== g.x || y !== g.y)
        window.frameGeometry = { x: x, y: y, width: g.width, height: g.height };
});
