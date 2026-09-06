var assert = require("assert");
var fs = require("fs");
var path = require("path");
var vm = require("vm");

var source = fs.readFileSync(path.join(__dirname, "Geometry.js"), "utf8");
var context = {};
vm.createContext(context);
vm.runInContext(source, context, { filename: "Geometry.js" });

function finiteValues(values) {
    return values.every(function (value) { return typeof value === "number" && isFinite(value); });
}

function pathNumbers(value) {
    return value.match(/-?(?:\d+\.?\d*|\.\d+)/g).map(Number);
}

function dateKey(value) {
    return [value.getFullYear(), value.getMonth(), value.getDate()].join("/");
}

function largestDelta(left, right) {
    return left.reduce(function (largest, value, index) {
        return Math.max(largest, Math.abs(value - right[index]));
    }, 0);
}

var spring = context.springCurve(0.8);
var critical = context.springCurve(1);
assert(Array.isArray(spring) && spring.length % 6 === 0 && spring.length > 6);
assert.strictEqual(spring.length, 48);
assert(finiteValues(spring) && finiteValues(critical));
assert.strictEqual(spring[spring.length - 2], 1);
assert.strictEqual(spring[spring.length - 1], 1);
assert(spring.some(function (value, index) { return index % 2 === 1 && value > 1.0001; }));
assert(!critical.some(function (value, index) { return index % 2 === 1 && value > 1.0001; }));
for (var i = 0; i < spring.length; i += 6) {
    assert(spring[i] < spring[i + 2] && spring[i + 2] < spring[i + 4]);
    if (i) {
        assert(spring[i] > spring[i - 2]);
    }
}

var paths = [0, 0.25, 0.5, 0.75, 1].map(function (morph) {
    return context.outline(320, 120, morph);
});
var shapeNumbers = paths.map(pathNumbers);
assert(paths.every(function (value) { return value.indexOf("NaN") === -1; }));
assert(shapeNumbers.every(function (value) { return value.length === shapeNumbers[0].length && finiteValues(value); }));
assert(shapeNumbers[0].some(function (value) { return value === 19; }));
assert(shapeNumbers[4].some(function (value) { return value === 0; }));
assert(paths[0].indexOf("Q") !== -1 && paths[4].indexOf("Q") !== -1);
assert(paths[0].indexOf("Q 320 0 320 19") !== -1);
assert(paths[4].indexOf("Q 306 0 306 14") !== -1 && paths[4].indexOf("V 101") !== -1);
assert(largestDelta(pathNumbers(context.outline(320, 120, 0.499)), pathNumbers(context.outline(320, 120, 0.501))) < 1);
assert(pathNumbers(paths[0]).every(function (value) { return value >= 0 && value <= 320; }));
assert(pathNumbers(paths[4]).every(function (value) { return value >= 0 && value <= 320; }));

var leap = context.monthCells(2024, 1);
assert(leap.length === 42);
assert(leap.some(function (value) { return dateKey(value) === "2024/1/29"; }));
assert.strictEqual(leap[0].getDay(), 1);
var yearBoundary = context.monthCells(2023, 0);
assert.strictEqual(dateKey(yearBoundary[0]), "2022/11/26");
assert.strictEqual(dateKey(yearBoundary[41]), "2023/1/5");
var offsetStart = new Date(2024, 0, 31, 12);
var offsetEnd = context.dateOffset(offsetStart, 1);
assert.strictEqual(dateKey(offsetEnd), "2024/1/1");
assert.strictEqual(dateKey(offsetStart), "2024/0/31");
var yearEnd = new Date(2023, 11, 31, 12);
assert.strictEqual(dateKey(context.dateOffset(yearEnd, 1)), "2024/0/1");

var dstBefore = new Date(2024, 2, 9, 12);
var dstAfter = context.dateOffset(dstBefore, 1);
assert.strictEqual(dateKey(dstAfter), "2024/2/10");
assert.strictEqual(dstAfter.getHours(), dstBefore.getHours());

assert.strictEqual(context.formatDuration(0), "0:00");
assert.strictEqual(context.formatDuration(65.9), "1:05");
assert.strictEqual(context.formatDuration(3601), "60:01");
assert.strictEqual(context.formatDuration(-3), "0:00");
assert.strictEqual(context.formatDuration(NaN), "0:00");

console.log("geometry checks passed");
