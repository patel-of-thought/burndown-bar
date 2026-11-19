import Foundation

enum ArtificialAnalysisTests {
    static func run() -> Int {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        let rows: JSON = ["data": [
            ["id": "one", "name": "Claude Fable 5.2 (Max, Default Fallback)",
             "model_creator": ["name": "Anthropic"],
             "evaluations": ["artificial_analysis_intelligence_index": 65],
             "artificial_analysis_intelligence_index_cost": ["cost_per_task": ["total_cost": 26.54]],
             "performance_v3": ["time_per_task_seconds": 2472]],
            ["id": "two", "name": "GPT-6.2 Astra (Max)",
             "model_creator": ["name": "OpenAI"],
             "evaluations": ["artificial_analysis_intelligence_index": 62],
             "artificial_analysis_intelligence_index_cost": ["cost_per_task": ["total_cost": 4.0]],
             "performance_v3": [:]]
        ]]
        let models = ArtificialAnalysisParser.models(rows)
        check(models.count == 2 && models[0].intelligence == 65 && models[0].costPerTaskUSD == 26.54,
              "Artificial Analysis index and cost per task parsed")
        check(models[0].minutesPerTask == 41.2 && models[1].minutesPerTask == nil,
              "Pro time per task converts seconds and missing free values stay unknown")
        let publicHTML = Data("<html><body><table><tbody><tr><td>Claude Fable 5.2 Max, Default Fallback</td><td>65</td><td>$26.54</td><td>41.2</td></tr><tr><td>GPT-6.2 Astra Max</td><td>62</td><td>$4.00</td><td>--</td></tr></tbody></table></body></html>".utf8)
        let times = ArtificialAnalysisParser.publicTimes(from: publicHTML)
        check(times[ArtificialAnalysisParser.normalizedName(models[0].name)] == 41.2
              && times[ArtificialAnalysisParser.normalizedName(models[1].name)] == nil,
              "public leaderboard time rows match model names without fabricating missing values")
        return passed
    }
}
