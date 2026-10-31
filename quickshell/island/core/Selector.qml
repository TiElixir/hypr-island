import QtQuick

// Picks the primary activity and the runner-up from the registered list.
QtObject {
    id: sel

    // JS array of Activity objects (see activities/Registry.qml)
    property var activities: []

    readonly property var sorted: {
        const arr = [];
        for (let i = 0; i < activities.length; i++) {
            if (activities[i].live)
                arr.push(activities[i]);
        }
        arr.sort((a, b) => b.effectivePriority - a.effectivePriority);
        return arr;
    }
    readonly property var primary: sorted.length > 0 ? sorted[0] : null
    readonly property var secondary: sorted.length > 1 ? sorted[1] : null
}
