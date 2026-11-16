#platform ""
#    requires { main! : () => {} }
#    packages {}
#    provides { "roc_main": main_for_host! }
#    hosted {}
#    targets: {
#        inputs_dir: "targets/",
#        x64musl: { inputs: [] },
#    }
