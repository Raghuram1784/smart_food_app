# Re-fetch licensed bundled source assets. Run from project root.
$ErrorActionPreference = 'Stop'
$photos = @{ burger=1639557; pizza=825661; pasta=1437267; salad=1211887 }
foreach ($name in $photos.Keys) {
    $id = $photos[$name]
    Invoke-WebRequest -Uri "https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg?auto=compress&cs=tinysrgb&w=1800" -OutFile "assets/images/food/$name.jpg"
}
foreach ($font in @('BricolageGrotesque','Sora','Fraunces')) {
    $folder = $font.ToLower()
    $file = switch ($font) { 'BricolageGrotesque' { 'BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf' } 'Sora' { 'Sora%5Bwght%5D.ttf' } default { 'Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf' } }
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/google/fonts/main/ofl/$folder/$file" -OutFile "assets/fonts/$font.ttf"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/google/fonts/main/ofl/$folder/OFL.txt" -OutFile "assets/fonts/$font-OFL.txt"
}
python tool/prepare_assets.py

$indianPhotos = @{ dosa=12392915; idli=17869141; biryani=35041655; paneer=12737816 }
foreach ($name in $indianPhotos.Keys) {
    $id = $indianPhotos[$name]
    Invoke-WebRequest -Uri "https://images.pexels.com/photos/$id/pexels-photo-$id.jpeg?auto=compress&cs=tinysrgb&w=2400" -OutFile "assets/images/food/$name.jpg"
}
python tool/refine_assets.py
