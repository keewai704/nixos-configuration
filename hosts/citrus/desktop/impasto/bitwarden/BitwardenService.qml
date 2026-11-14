pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

Singleton {
    id: root

    readonly property string copyScript: Quickshell.shellPath("bitwarden/copy.sh")
    readonly property int clipboardSeconds: 30
    readonly property int totpPeriod: 30
    readonly property int enrichLimit: 80

    property string view: "checking"
    property string problem: ""
    property string notice: ""
    property string copyNotice: ""
    property string setupError: ""

    property string accountEmail: ""
    property string accountBaseUrl: ""
    property string draftEmail: ""
    property string draftBaseUrl: ""
    property bool editingAccount: false

    property var items: []
    property var details: ({})
    property string selectedId: ""
    property string detailError: ""
    property var revealed: ({})
    property string totpCode: ""
    property int totpLeft: 0
    property string totpFetchId: ""

    property string search: ""
    property int filterIndex: 0
    property var filterLabels: []
    property var filterKinds: ["all"]

    property bool live: false
    property var queue: []
    property string pendingDetail: ""
    property string pendingBaseUrl: ""
    property string copyLabel: ""

    readonly property var rows: {
        const found = []
        const needle = root.search.trim().toLowerCase()
        const kind = root.filterKinds[root.filterIndex] ?? "all"
        for (const item of root.items) {
            if (!root.passes(item, kind))
                continue
            if (needle !== "" && !root.matches(item, needle))
                continue
            found.push(item)
        }
        return found
    }

    readonly property var selectedItem: {
        if (root.selectedId === "")
            return null
        for (const item of root.items) {
            if (item.id === root.selectedId)
                return item
        }
        return null
    }

    readonly property var selectedDetail: root.selectedId === "" ? null : (root.details[root.selectedId] ?? null)
    readonly property string selectedType: root.entryType(root.selectedItem, root.selectedDetail)
    readonly property var selectedData: root.dataOf(root.selectedDetail)

    readonly property bool selectedHasTotp: {
        const data = root.selectedData
        return !!data && root.isSet(data.totp)
    }

    readonly property string totpDisplay: {
        if (root.totpCode === "")
            return root.mask()
        if (root.totpCode.length === 6)
            return root.totpCode.slice(0, 3) + " " + root.totpCode.slice(3)
        return root.totpCode
    }

    readonly property var uris: {
        const data = root.selectedData
        const list = data && Array.isArray(data.uris) ? data.uris : []
        const found = []
        list.forEach((entry, index) => {
            const uri = typeof entry === "string" ? entry : (entry?.uri ?? "")
            if (uri.trim() === "")
                return
            found.push({ key: "uri:" + index, uri: uri, mode: "uri:" + index })
        })
        return found
    }

    readonly property var customFields: {
        const detail = root.selectedDetail
        const fields = detail && Array.isArray(detail.fields) ? detail.fields : []
        const found = []
        fields.forEach((field, index) => {
            found.push({
                key: "custom:" + index,
                name: root.isSet(field.name) ? field.name.trim() : Tr.t("Custom field"),
                value: root.isSet(field.value) ? field.value : "",
                kind: field.type ?? "text",
                mode: "field:" + index
            })
        })
        return found
    }

    readonly property var history: {
        const detail = root.selectedDetail
        const entries = detail && Array.isArray(detail.history) ? detail.history : []
        const found = []
        entries.forEach((entry, index) => {
            found.push({
                key: "history:" + index,
                date: root.dateOf(entry.last_used_date),
                password: entry.password ?? "",
                mode: "history:" + index
            })
        })
        return found
    }

    readonly property string notes: root.selectedDetail && root.isSet(root.selectedDetail.notes)
        ? root.selectedDetail.notes : ""

    readonly property string itemFolder: root.selectedDetail && root.isSet(root.selectedDetail.folder)
        ? root.selectedDetail.folder
        : (root.selectedItem && root.isSet(root.selectedItem.folder) ? root.selectedItem.folder : "")

    readonly property string cardBrand: root.selectedData && root.isSet(root.selectedData.brand)
        ? root.selectedData.brand.trim() : ""

    readonly property string cardExpiry: root.selectedData
        ? root.expiry(root.selectedData.exp_month, root.selectedData.exp_year) : ""

    readonly property string identityFullName: root.identityName(root.selectedData)
    readonly property string identityAddress: root.addressLines(root.selectedData)

    readonly property Timer clipboardTimer: Timer {
        interval: root.clipboardSeconds * 1000

        onTriggered: {
            Quickshell.execDetached(["wl-copy", "--clear"])
            root.copyNotice = Tr.t("Clipboard cleared")
            root.noticeTimer.restart()
        }
    }

    readonly property Timer noticeTimer: Timer {
        interval: 4000

        onTriggered: root.copyNotice = ""
    }

    readonly property Timer ticker: Timer {
        interval: 1000
        repeat: true
        running: root.view === "ready" && root.selectedHasTotp

        onTriggered: root.tick()
    }

    readonly property Process probeProcess: Process {
        command: ["sh", "-c", "command -v rbw"]

        onExited: code => root.probeFinished(code)
    }

    readonly property Process configProcess: Process {
        command: ["rbw", "config", "show"]
        stdout: StdioCollector { id: configOut }
        stderr: StdioCollector { id: configErr }

        onExited: code => root.configFinished(code, configOut.text, configErr.text)
    }

    readonly property Process unlockedProcess: Process {
        command: ["rbw", "unlocked"]
        stderr: StdioCollector { id: unlockedErr }

        onExited: code => root.unlockedFinished(code, unlockedErr.text)
    }

    readonly property Process unlockProcess: Process {
        command: ["rbw", "unlock"]
        stderr: StdioCollector { id: unlockErr }

        onExited: code => root.unlockFinished(code, unlockErr.text)
    }

    readonly property Process lockProcess: Process {
        command: ["rbw", "lock"]
        stderr: StdioCollector { id: lockErr }

        onExited: code => root.lockFinished(code, lockErr.text)
    }

    readonly property Process syncProcess: Process {
        command: ["rbw", "sync"]
        stderr: StdioCollector { id: syncErr }

        onExited: code => root.syncFinished(code, syncErr.text)
    }

    readonly property Process listProcess: Process {
        command: ["rbw", "list", "--raw"]
        stdout: StdioCollector { id: listOut }
        stderr: StdioCollector { id: listErr }

        onExited: code => root.listFinished(code, listOut.text, listErr.text)
    }

    readonly property Process getProcess: Process {
        stdout: StdioCollector { id: getOut }
        stderr: StdioCollector { id: getErr }

        onExited: code => root.detailFinished(code, getOut.text, getErr.text)
    }

    readonly property Process codeProcess: Process {
        stdout: StdioCollector { id: codeOut }

        onExited: code => root.codeFinished(code, codeOut.text)
    }

    readonly property Process emailProcess: Process {
        stderr: StdioCollector { id: emailErr }

        onExited: code => root.emailFinished(code, emailErr.text)
    }

    readonly property Process baseUrlProcess: Process {
        stderr: StdioCollector { id: baseUrlErr }

        onExited: code => root.baseUrlFinished(code, baseUrlErr.text)
    }

    readonly property Process copyProcess: Process {
        stderr: StdioCollector { id: copyErr }

        onExited: code => root.copyFinished(code, copyErr.text)
    }

    function isSet(value) {
        return typeof value === "string" && value.trim() !== ""
    }

    function firstLine(value) {
        const text = (value ?? "").trim()
        if (text === "")
            return ""
        return text.split("\n")[0].trim()
    }

    function mask() {
        return "••••••••"
    }

    function digits(value) {
        return (value ?? "").replace(/[^0-9]/g, "")
    }

    function cardNumber(value) {
        const only = root.digits(value)
        const groups = []
        for (let index = 0; index < only.length; index += 4)
            groups.push(only.slice(index, index + 4))
        return groups.join(" ")
    }

    function maskedCard(value) {
        const only = root.digits(value)
        if (only.length <= 4)
            return "•••• •••• •••• " + only
        return "•••• •••• •••• " + only.slice(-4)
    }

    function expiry(month, year) {
        let head = (month ?? "").toString().trim()
        const tail = (year ?? "").toString().trim()
        if (head === "" && tail === "")
            return ""
        if (head.length === 1)
            head = "0" + head
        if (tail === "")
            return head
        if (head === "")
            return tail
        return head + "/" + tail
    }

    function identityName(data) {
        if (!data)
            return ""
        const parts = []
        for (const key of ["title", "first_name", "middle_name", "last_name"]) {
            if (root.isSet(data[key]))
                parts.push(data[key].trim())
        }
        return parts.join(" ")
    }

    function addressLines(data) {
        if (!data)
            return ""
        const lines = []
        for (const key of ["address1", "address2", "address3"]) {
            if (root.isSet(data[key]))
                lines.push(data[key].trim())
        }
        const region = []
        for (const key of ["city", "state"]) {
            if (root.isSet(data[key]))
                region.push(data[key].trim())
        }
        let regionText = region.join(", ")
        if (root.isSet(data.postal_code))
            regionText = regionText === "" ? data.postal_code.trim() : regionText + " " + data.postal_code.trim()
        if (regionText !== "")
            lines.push(regionText)
        if (root.isSet(data.country))
            lines.push(data.country.trim())
        return lines.join("\n")
    }

    function dateOf(iso) {
        if (typeof iso !== "string")
            return ""
        const match = iso.match(/^\d{4}-\d{2}-\d{2}/)
        return match ? match[0] : iso
    }

    function dataOf(detail) {
        if (!detail || typeof detail.data !== "object" || detail.data === null)
            return null
        return detail.data
    }

    function entryType(item, detail) {
        if (item && root.isSet(item.type))
            return item.type
        const data = root.dataOf(detail)
        if (!data)
            return "Note"
        if ("cardholder_name" in data || "number" in data || "brand" in data)
            return "Card"
        if ("public_key" in data || "private_key" in data)
            return "SSH Key"
        if ("first_name" in data || "last_name" in data || "ssn" in data || "address1" in data)
            return "Identity"
        if ("username" in data || "password" in data || "totp" in data || "uris" in data)
            return "Login"
        return "Note"
    }

    function typeGlyph(type) {
        if (type === "Card")
            return "󰠗"
        if (type === "Identity")
            return "󰗹"
        if (type === "Note")
            return "󰎞"
        if (type === "SSH Key")
            return "󰌆"
        return "󰌾"
    }

    function typeLabel(type) {
        if (type === "Card")
            return Tr.t("Card")
        if (type === "Identity")
            return Tr.t("Identity")
        if (type === "Note")
            return Tr.t("Secure note")
        if (type === "SSH Key")
            return Tr.t("SSH key")
        return Tr.t("Login")
    }

    function passes(item, kind) {
        if (kind === "all" || kind === undefined)
            return true
        if (kind.indexOf("folder:") === 0)
            return (item.folder ?? "") === kind.slice(7)
        return item.type === kind
    }

    function matches(item, needle) {
        const values = [item.name, item.user, item.folder]
        const uris = Array.isArray(item.uris) ? item.uris : []
        for (const entry of uris)
            values.push(typeof entry === "string" ? entry : entry?.uri)
        for (const value of values) {
            if (typeof value === "string" && value.toLowerCase().indexOf(needle) >= 0)
                return true
        }
        return false
    }

    function subtitleOf(item) {
        const detail = root.details[item.id] ?? null
        const type = root.entryType(item, detail)
        const data = root.dataOf(detail)
        if (type === "Login")
            return root.isSet(item.user) ? item.user : Tr.t("No username")
        if (type === "Card") {
            const brand = data && root.isSet(data.brand) ? data.brand.trim() : ""
            const number = data && root.isSet(data.number) ? root.digits(data.number) : ""
            if (brand !== "" && number !== "")
                return brand + " •••• " + number.slice(-4)
            if (brand !== "")
                return brand
            return root.isSet(item.folder) ? item.folder : Tr.t("Card")
        }
        if (type === "Identity") {
            const name = root.identityName(data)
            if (name !== "")
                return name
            return root.isSet(item.folder) ? item.folder : Tr.t("Identity")
        }
        if (type === "SSH Key") {
            if (root.isSet(item.user))
                return item.user
            return root.isSet(item.folder) ? item.folder : Tr.t("SSH key")
        }
        return root.isSet(item.folder) ? item.folder : Tr.t("Secure note")
    }

    function rebuildFilters() {
        const labels = [
            Tr.t("All items"), Tr.t("Login"), Tr.t("Card"),
            Tr.t("Identity"), Tr.t("Note"), Tr.t("SSH key")
        ]
        const kinds = ["all", "Login", "Card", "Identity", "Note", "SSH Key"]
        const folders = []
        for (const item of root.items) {
            if (root.isSet(item.folder) && folders.indexOf(item.folder) < 0)
                folders.push(item.folder)
        }
        folders.sort()
        for (const folder of folders) {
            labels.push(folder)
            kinds.push("folder:" + folder)
        }
        root.filterLabels = labels
        root.filterKinds = kinds
        if (root.filterIndex >= labels.length)
            root.filterIndex = 0
    }

    function begin() {
        root.live = true
        root.editingAccount = false
        root.copyNotice = ""
        root.check()
    }

    function check() {
        root.dropSensitive()
        root.problem = ""
        root.notice = ""
        root.setupError = ""
        root.view = "checking"
        root.probeProcess.running = true
    }

    function probeFinished(code) {
        if (!root.live)
            return
        if (code !== 0) {
            root.view = "no_rbw"
            return
        }
        root.configProcess.running = true
    }

    function configFinished(code, out, err) {
        if (!root.live)
            return
        if (code !== 0) {
            root.accountEmail = ""
            root.accountBaseUrl = ""
            root.draftEmail = ""
            root.draftBaseUrl = ""
            root.view = "setup"
            return
        }
        let parsed = null
        try {
            parsed = JSON.parse(out)
        } catch (error) {
            parsed = null
        }
        root.accountEmail = parsed && root.isSet(parsed.email) ? parsed.email.trim() : ""
        root.accountBaseUrl = parsed && root.isSet(parsed.base_url) ? parsed.base_url.trim() : ""
        root.draftEmail = root.accountEmail
        root.draftBaseUrl = root.accountBaseUrl
        if (root.accountEmail === "") {
            root.view = "setup"
            return
        }
        root.unlockedProcess.running = true
    }

    function unlockedFinished(code, err) {
        if (!root.live)
            return
        if (code === 0) {
            root.startList(false)
            return
        }
        root.view = "locked"
        root.problem = root.lockedBody(err)
    }

    function lockedBody(value) {
        const text = (value ?? "").trim()
        if (text === "")
            return ""
        const lowered = text.toLowerCase()
        if (lowered.indexOf("not running") >= 0 || lowered.indexOf("lock") >= 0 || lowered.indexOf("unlock") >= 0)
            return ""
        return text
    }

    function unlock() {
        if (root.view === "unlocking")
            return
        root.problem = ""
        root.notice = ""
        root.view = "unlocking"
        root.unlockProcess.running = true
    }

    function unlockFinished(code, err) {
        if (!root.live)
            return
        if (code !== 0) {
            root.view = "locked"
            root.problem = root.firstLine(err)
            return
        }
        root.startList(true)
    }

    function lock() {
        if (root.view === "ready" || root.view === "error")
            root.lockProcess.running = true
    }

    function lockFinished(code, err) {
        if (!root.live)
            return
        root.dropSensitive()
        root.view = "locked"
        root.problem = code === 0 ? "" : root.firstLine(err)
    }

    function sync() {
        if (root.view !== "ready")
            return
        root.startList(true)
    }

    function startList(withSync) {
        root.problem = ""
        root.notice = ""
        root.view = "syncing"
        if (withSync) {
            root.syncProcess.running = true
            return
        }
        root.listProcess.running = true
    }

    function syncFinished(code, err) {
        if (!root.live)
            return
        if (code !== 0)
            root.notice = root.firstLine(err)
        root.listProcess.running = true
    }

    function listFinished(code, out, err) {
        if (!root.live)
            return
        if (code !== 0) {
            const message = root.firstLine(err)
            if (message.toLowerCase().indexOf("lock") >= 0) {
                root.dropSensitive()
                root.view = "locked"
                root.problem = ""
                return
            }
            root.view = "error"
            root.problem = message
            return
        }
        let parsed = null
        try {
            parsed = JSON.parse(out)
        } catch (error) {
            parsed = null
        }
        if (!Array.isArray(parsed)) {
            root.view = "error"
            root.problem = Tr.t("The vault answered something unexpected")
            return
        }
        const kept = root.selectedId
        root.items = parsed
        root.details = ({})
        root.queue = []
        root.revealed = ({})
        root.totpCode = ""
        root.totpLeft = 0
        root.totpFetchId = ""
        root.detailError = ""
        root.selectedId = ""
        root.rebuildFilters()
        root.view = "ready"
        if (kept !== "" && parsed.some(item => item.id === kept))
            root.select(kept)
        root.enrich()
    }

    function enrich() {
        let queued = 0
        for (const item of root.items) {
            if (queued >= root.enrichLimit)
                return
            const type = root.entryType(item, null)
            if (type !== "Card" && type !== "Identity")
                continue
            if (root.details[item.id])
                continue
            queued += 1
            root.requestDetail(item.id, false)
        }
    }

    function select(id) {
        if (id === "" || id === root.selectedId)
            return
        root.selectedId = id
        root.revealed = ({})
        root.totpCode = ""
        root.totpLeft = 0
        root.detailError = ""
        const cached = root.details[id] ?? null
        if (cached)
            root.afterDetail(id, cached)
        else
            root.requestDetail(id, true)
    }

    function requestDetail(id, front) {
        if (id === "")
            return
        const cached = root.details[id] ?? null
        if (cached) {
            root.afterDetail(id, cached)
            return
        }
        const at = root.queue.indexOf(id)
        if (at >= 0) {
            if (front && at > 0) {
                root.queue.splice(at, 1)
                root.queue.unshift(id)
            }
        } else if (front) {
            root.queue.unshift(id)
        } else {
            root.queue.push(id)
        }
        root.pump()
    }

    function pump() {
        if (root.getProcess.running || root.queue.length === 0)
            return
        const id = root.queue.shift()
        root.pendingDetail = id
        root.getProcess.command = ["rbw", "get", "--raw", id]
        root.getProcess.running = true
    }

    function detailFinished(code, out, err) {
        if (!root.live)
            return
        const id = root.pendingDetail
        root.pendingDetail = ""
        if (id !== "" && code === 0) {
            let parsed = null
            try {
                parsed = JSON.parse(out)
            } catch (error) {
                parsed = null
            }
            if (parsed) {
                const next = Object.assign({}, root.details)
                next[id] = parsed
                root.details = next
                if (id === root.selectedId)
                    root.afterDetail(id, parsed)
            } else if (id === root.selectedId) {
                root.detailError = Tr.t("The item answered something unexpected")
            }
        } else if (id !== "" && id === root.selectedId) {
            const message = root.firstLine(err)
            if (message.toLowerCase().indexOf("lock") >= 0) {
                root.dropSensitive()
                root.view = "locked"
                root.problem = ""
                return
            }
            root.detailError = message
        }
        Qt.callLater(root.pump)
    }

    function afterDetail(id, detail) {
        root.detailError = ""
        const data = root.dataOf(detail)
        if (!data || !root.isSet(data.totp))
            return
        if (root.totpLeft === 0)
            root.totpLeft = root.totpPeriod - (Math.floor(Date.now() / 1000) % root.totpPeriod)
        if (root.totpCode === "")
            root.fetchCode(id)
    }

    function fetchCode(id) {
        if (id === "" || root.codeProcess.running)
            return
        root.totpFetchId = id
        root.codeProcess.command = ["rbw", "code", id]
        root.codeProcess.running = true
    }

    function codeFinished(code, out) {
        if (!root.live)
            return
        const id = root.totpFetchId
        root.totpFetchId = ""
        if (code !== 0 || id === "" || id !== root.selectedId)
            return
        const value = out.trim()
        if (value === "")
            return
        root.totpCode = value
        root.totpLeft = root.totpPeriod - (Math.floor(Date.now() / 1000) % root.totpPeriod)
    }

    function tick() {
        if (!root.selectedHasTotp)
            return
        const left = root.totpPeriod - (Math.floor(Date.now() / 1000) % root.totpPeriod)
        const rolled = root.totpLeft > 0 && left > root.totpLeft
        root.totpLeft = left
        if (rolled)
            root.fetchCode(root.selectedId)
    }

    function toggleReveal(key) {
        if (key === "")
            return
        const next = Object.assign({}, root.revealed)
        if (next[key] === true)
            delete next[key]
        else
            next[key] = true
        root.revealed = next
    }

    function copy(mode, label) {
        if (root.selectedId === "" || mode === "")
            return
        root.copyLabel = label
        root.copyProcess.command = [root.copyScript, mode, root.selectedId]
        root.copyProcess.running = true
    }

    function copyFinished(code, err) {
        if (code === 0) {
            root.copyNotice = Tr.t("Copied %1").arg(root.copyLabel)
            root.clipboardTimer.restart()
        } else {
            root.copyNotice = root.firstLine(err) !== "" ? root.firstLine(err) : Tr.t("Could not copy")
        }
        root.noticeTimer.restart()
    }

    function openUri(uri) {
        if (uri === "")
            return
        Quickshell.execDetached(["xdg-open", uri])
    }

    function editAccount() {
        root.draftEmail = root.accountEmail
        root.draftBaseUrl = root.accountBaseUrl
        root.setupError = ""
        root.editingAccount = true
    }

    function cancelAccount() {
        root.setupError = ""
        root.editingAccount = false
    }

    function saveAccount() {
        const email = root.draftEmail.trim()
        const baseUrl = root.draftBaseUrl.trim()
        if (email === "") {
            root.setupError = Tr.t("An account email is required")
            return
        }
        if (baseUrl !== "" && !/^https?:\/\//.test(baseUrl)) {
            root.setupError = Tr.t("The server URL starts with http:// or https://")
            return
        }
        root.setupError = ""
        root.pendingBaseUrl = baseUrl
        root.emailProcess.command = ["rbw", "config", "set", "email", email]
        root.emailProcess.running = true
    }

    function emailFinished(code, err) {
        if (!root.live)
            return
        if (code !== 0) {
            root.setupError = root.firstLine(err) !== "" ? root.firstLine(err)
                : Tr.t("Could not write the rbw configuration")
            return
        }
        if (root.pendingBaseUrl === "") {
            root.accountSaved()
            return
        }
        root.baseUrlProcess.command = ["rbw", "config", "set", "base_url", root.pendingBaseUrl]
        root.baseUrlProcess.running = true
    }

    function baseUrlFinished(code, err) {
        if (!root.live)
            return
        if (code !== 0) {
            root.setupError = root.firstLine(err) !== "" ? root.firstLine(err)
                : Tr.t("Could not write the rbw configuration")
            return
        }
        root.accountSaved()
    }

    function accountSaved() {
        root.accountEmail = root.draftEmail.trim()
        root.accountBaseUrl = root.draftBaseUrl.trim()
        root.editingAccount = false
        root.check()
    }

    function dismiss() {
        root.live = false
        root.dropSensitive()
        root.problem = ""
        root.notice = ""
        root.copyNotice = ""
        root.setupError = ""
        root.editingAccount = false
        root.view = "checking"
    }

    function dropSensitive() {
        root.items = []
        root.details = ({})
        root.queue = []
        root.selectedId = ""
        root.revealed = ({})
        root.totpCode = ""
        root.totpLeft = 0
        root.totpFetchId = ""
        root.detailError = ""
        root.search = ""
        root.filterIndex = 0
        root.filterLabels = []
        root.filterKinds = ["all"]
    }
}
