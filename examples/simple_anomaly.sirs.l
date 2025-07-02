{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "i32",
        "body": [
          {
            "let": {
              "name": "baseline_mean",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"literal": 100.0},
                    {"literal": 10.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "baseline_std",
              "value": {
                "sample": {
                  "distribution": "lognormal", 
                  "params": [
                    {"literal": 1.0},
                    {"literal": 0.5}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_anomaly",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"literal": 0.05}]
                }
              }
            }
          },
          {
            "let": {
              "name": "observed_metric",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"var": "baseline_mean"},
                    {"var": "baseline_std"}
                  ]
                }
              }
            }
          },
          {
            "return": {"literal": 42}
          }
        ]
      }
    }
  }
}