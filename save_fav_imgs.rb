#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'logger'
require 'optparse'
require 'kconv'
require 'rubygems'
require 'net/http'
require 'open-uri'
require 'json'
require 'oauth'

Net::HTTP.version_1_2

# 設定読込
File.open("#{__dir__}/save_fav_imgs.json") do |f|
	ini = JSON.load(f)
	Log = Logger.new(ini['log_file'], 3)
	Log.info('--Start-------------------')
	$LAST_ID_FILE = ini['apl_data_file']
	$FAV_URL = "https://api.twitter.com/1.1/favorites/list.json?count=200&screen_name=#{ini['screen_name']}&tweet_mode=extended";
	$GET_STATUS= "https://api.twitter.com/1.1/statuses/lookup.json?include_entities=true&include_ext_alt_text=true&tweet_mode=extended";
	$SAVE_DIR = ini['save_dir']
	$M3U8_DOWNLOAD_COMMAND = ini['m3u8_download_command'] || ''
	$ACCESS_TOKEN = OAuth::AccessToken.new(
		OAuth::Consumer.new(
			ini['oauth']['consumer_key'],
			ini['oauth']['consumer_key_secret'],
			{:site=>'https://api.twitter.com'}
		),
		ini['oauth']['access_token'],
		ini['oauth']['access_token_secret']
	)
end

# API実行
$USER_AGENT = 'save_fav_imgs'
def twitter_execute(uri)
	Log.debug("execute-api #{uri}");
	5.times {
		begin
			res = ''
			Timeout.timeout(60) {
				res = $ACCESS_TOKEN.get(uri, {'User-Agent' => $USER_AGENT})
			}
			case res
			when Net::HTTPSuccess then
				return res.body
			when Net::HTTPNotFound, Net::HTTPForbidden, Net::HTTPBadGateway then
				Log.error("unretryable error. responce code #=> #{res.code} msg #=> #{res.message}")
				Log.debug(res.body)
				return nil
			when Net::HTTPRedirection then
				uri = res['location']
				Log.info("redirect to #{uri}")
			else
				Log.warn("unknown responce code #=> #{res.code} msg #=> #{res.message}")
				Log.debug(res.body)
			end
		rescue => e
			Log.warn(e)
		end
		Log.info('sleep 2 sec and retry.')
		sleep(2)
	}
	Log.error("retry over !!!")
	return nil
end

# ユーティリティ
def comp_id(a, b)
	return 0 if a == b
	return -1 if a == nil
	return 1 if b == nil
	return (a.size < b.size || a < b) ? -1 : 1
end

# 保存メイン
def save_images(json, since_id = '', max_id = nil)
	last_id = since_id
	first_id = max_id
	Log.warn("json #=> nil") if json == nil || json.empty?
	json_obj = JSON.parse(json)
	json_obj.map { |status|
		# IDチェック
		id = status['id_str'];
		break if comp_id(id, since_id) <= 0 && max_id.to_s.empty? == nil
		last_id = id if comp_id(last_id, id) < 0
		first_id = id if comp_id(id, first_id) < 0 || first_id.to_s.empty?
		# ツイートの情報を取得する
		Log.debug("id => #{id}");
		entities = status['extended_entities']
		next if entities == nil
		media = entities['media']
		next if media == nil
		# ツイートの情報からディレクトリ名とファイル名を作成する
		screen_name = status['user']['screen_name']
		created_at = Time::parse(status['created_at']).localtime.strftime('%Y%m%d_%H%M%S')
		text = (status['text'] || status['full_text']).strip
		escaped_text = text.gsub(/http.+/, '').gsub(/[\\\/:*?"<>|()]|\s/, '_').sub(/_+$/, '')
		dir = "#{$SAVE_DIR}/@#{screen_name}"
		file_name = "#{created_at}_#{escaped_text}"
		file_name = file_name[0..47] + '...' if 50 < file_name.size
		file_path = "#{dir}/#{file_name}"
		# メディアファイルを保存する
		Dir.mkdir(dir, 0755) if !Dir.exists?(dir)
		Log.info("media.map.size => #{media.map.size}")
		index = 0
		has_other_medias = 1 < media.map.size
		media.map { |m|
			index += 1
			video_info = m['video_info']
			url = video_info == nil ? m['media_url'] : video_info['variants'][0]['url'] # 画像のURL or 動画のURL
			ext = url.sub(/.+\//, '').sub(/.+\./, '').sub(/[\?#;].*/, '')
			index_str = has_other_medias ? "_#{index}" : ''
			file_path = "#{dir}/#{file_name}#{index_str}.#{ext}"
			Log.info("file_path #=> #{file_path}")
			next if File.exists?(file_path)
			if ext == 'm3u8'
				cmd = $M3U8_DOWNLOAD_COMMAND.sub('$url', url).sub('$file_path', file_path.sub(/m3u8$/, 'mp4'))
				Log.debug(cmd)
				system(cmd)
			else
				open(file_path, 'wb') { |local_file|
						URI.open(url) { |remote_file|
						local_file.write(remote_file.read)
					}
				}
			end
		}
	}
	return last_id, first_id
end

# ------------
# START HERE !
# ------------
opts = OptionParser.new
last_id = ''
max_id = nil
roop_count = 1
target_id = nil
opts.on('-r VALUE', '--roop VALUE', Integer, 'roop count') { |r|
	roop_count = r
}
sleep_sec = 1
opts.on('-s VALUE', '--sleep VALUE', Integer, 'sleep seconds') { |s|
	sleep_sec = s
}
opts.on('-i VALUE', '--id VALUE', String, 'id') { |i|
	target_id = i
}
opts.parse!(ARGV)
if ARGV[0] && m = ARGV[0].match(/https:\/\/twitter.com\/[^\/]+\/status\/(\d+)/) then
	target_id = m[1]
end
if roop_count == 1
	open($LAST_ID_FILE, 'r') { |f|
		last_id = f.read
	}
end
if target_id
	url = $GET_STATUS
	url << "&id=#{target_id}"
	res = twitter_execute(url)
	#Log.debug(res)
	save_images(res)
else
	for i in 1..roop_count do
		sleep(sleep_sec) if i != 1
		url = $FAV_URL
		url << "&since_id=#{last_id}" if !last_id.to_s.empty? && roop_count == 1
		url << "&max_id=#{max_id}" if !max_id.to_s.empty? && roop_count != 1
		res = twitter_execute(url);
		last_id, max_id = save_images(res, last_id, max_id);
	end
	if roop_count == 1
		open($LAST_ID_FILE, 'w') { |f|
			f.write(last_id)
		}
		Log.info("last_id #{last_id}")
	end
end
Log.info('--End---------------------')

