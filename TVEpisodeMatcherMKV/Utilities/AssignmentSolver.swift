import Foundation

enum AssignmentSolver {
    // Returns an array where result[row] = column assignment
    static func hungarian(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        guard n > 0 else { return [] }
        let m = cost[0].count
        let size = max(n, m)

        // Build square matrix by padding with large cost
        let big = 1.0e9
        var a = Array(repeating: Array(repeating: big, count: size), count: size)
        for i in 0..<n {
            for j in 0..<m {
                a[i][j] = cost[i][j]
            }
        }

        var u = Array(repeating: 0.0, count: size + 1)
        var v = Array(repeating: 0.0, count: size + 1)
        var p = Array(repeating: 0, count: size + 1)
        var way = Array(repeating: 0, count: size + 1)

        for i in 1...size {
            p[0] = i
            var j0 = 0
            var minv = Array(repeating: Double.greatestFiniteMagnitude, count: size + 1)
            var used = Array(repeating: false, count: size + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.greatestFiniteMagnitude
                var j1 = 0
                for j in 1...size {
                    if used[j] { continue }
                    let cur = a[i0 - 1][j - 1] - u[i0] - v[j]
                    if cur < minv[j] {
                        minv[j] = cur
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                for j in 0...size {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }
                j0 = j1
            } while p[j0] != 0

            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }

        var assignment = Array(repeating: -1, count: size)
        for j in 1...size {
            if p[j] != 0 {
                assignment[p[j] - 1] = j - 1
            }
        }

        return Array(assignment.prefix(n))
    }
}
