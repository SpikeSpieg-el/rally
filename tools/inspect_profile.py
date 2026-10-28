"""Профиль кривой против задуманного (author_route): где кривая уходит в впадины."""
import importlib
import math
import sys

sys.path.insert(0, "/home/user/rally/tools")
import stage_model as model

ctrl = model.load_curve()
samples = model.sample_curve(ctrl, 1.0)

# накопленный XZ-путь по сэмплам (как bake_interval по длине — тут по XZ, у
# Godot по 3D; расхождение мало при уклонах < 30%)
acc = [0.0]
for i in range(1, len(samples)):
    acc.append(acc[-1] + math.dist(samples[i - 1][:1] + samples[i - 1][2:],
                                    samples[i][:1] + samples[i][2:]))
def h_at(xz):
    j = 0
    while j < len(acc) - 2 and acc[j + 1] < xz:
        j += 1
    t = (xz - acc[j]) / max(1e-6, acc[j + 1] - acc[j])
    return samples[j][1] + (samples[j + 1][1] - samples[j][1]) * t

print("контрольных точек: %d, длина(XZ) %.0f м" % (len(ctrl), acc[-1]))
print("\nКонтрольные точки (XZ-км, высота):")
cacc = [0.0]
for i in range(1, len(ctrl)):
    a = ctrl[i - 1][2]
    b = ctrl[i][2]
    cacc.append(cacc[-1] + math.dist((a[0], a[2]), (b[0], b[2])))
for i, (a, p) in enumerate(zip(cacc, [c[2] for c in ctrl])):
    pin = ctrl[i][0]
    hlen = math.dist((pin[0], pin[2]), (p[0], p[2]))
    print("  %3d  xz=%7.1f  h=%+7.2f  (ручка %.1f м)" % (i, a, p[1], hlen))

# Задуманный профиль: compose -> smooth -> limit_grade (как в author_route.main)
sys.path.insert(0, "/home/user/rally/tools")
import author_route as ar
raw, length = ar.compose()
pts = ar.resample(ar.limit_grade(ar.smooth_heights(raw, ar.HEIGHT_WINDOW), ar.MAX_GRADE_DEG), 1.0)
pacc = [0.0]
for i in range(1, len(pts)):
    pacc.append(pacc[-1] + math.dist(pts[i - 1][:2], pts[i][:2]))
def ph_at(xz):
    j = 0
    while j < len(pacc) - 2 and pacc[j + 1] < xz:
        j += 1
    t = (xz - pacc[j]) / max(1e-6, pacc[j + 1] - pacc[j])
    return pts[j][2] + (pts[j + 1][2] - pts[j][2]) * t

print("\nОтклонение кривой от замысла (каждые 10 м, |Δ|>0.3 м):")
worst = 0.0
for xz in range(10, int(acc[-1]) - 10, 10):
    d = h_at(float(xz)) - ph_at(float(xz))
    if abs(d) > 0.3:
        print("  xz %5d  кривая %+7.2f  замысел %+7.2f  Δ %+5.2f" % (xz, h_at(float(xz)), ph_at(float(xz)), d))
    worst = max(worst, abs(d))
print("худшее отклонение: %.2f м" % worst)
