{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "void",
        "body": [
          {
            "let": {
              "name": "hourly_baseline_traffic",
              "value": {
                "array": [
                  {"literal": 10.0},
                  {"literal": 5.0},
                  {"literal": 3.0},
                  {"literal": 15.0},
                  {"literal": 25.0},
                  {"literal": 30.0},
                  {"literal": 35.0},
                  {"literal": 20.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "seasonal_baseline",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "hourly_baseline_traffic"},
                  "index": {"literal": 6}
                }
              }
            }
          },
          {
            "let": {
              "name": "seasonal_variation_factor",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "lognormal",
                  "params": [
                    {"literal": 0.0},
                    {"literal": 0.2}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "trend_component",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "normal",
                  "params": [
                    {"literal": 1.05},
                    {"literal": 0.1}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "anomaly_spike_probability",
              "type": "f64",
              "value": {"literal": 0.05}
            }
          },
          {
            "let": {
              "name": "is_anomalous_period",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "anomaly_spike_probability"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "anomaly_multiplier",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 3.0},
                    {"literal": 1.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "expected_normal_traffic",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "seasonal_baseline"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "seasonal_variation_factor"},
                          {"var": "trend_component"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "expected_anomalous_traffic",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "expected_normal_traffic"},
                    {"var": "anomaly_multiplier"}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "predicted_traffic",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {
                            "op": {
                              "kind": "sub",
                              "args": [
                                {"literal": 1.0},
                                {"var": "is_anomalous_period"}
                              ]
                            }
                          },
                          {"var": "expected_normal_traffic"}
                        ]
                      }
                    },
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "is_anomalous_period"},
                          {"var": "expected_anomalous_traffic"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "observed_traffic",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"var": "predicted_traffic"}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "seasonal_baseline"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_anomalous_period"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "expected_normal_traffic"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "predicted_traffic"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_traffic"}]
              }
            }
          }
        ]
      }
    }
  }
}