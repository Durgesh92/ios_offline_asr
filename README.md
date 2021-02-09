# ios_offline_asr
Offline ASR Library for IOS

This app uses external library (dylib), if you are getting an error with the signatures you have to sign it with your own apple developer certificate

To sign external dylib

- remove public signature of lib
`codesign --remove-signature durgesh_ai.dylib`

- to sign lib
`codesign -s "Apple Development: your@mail (xxxxxxxxxx)" durgesh_ai.dylib`
