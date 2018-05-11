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
	Log.info('--開始--------------------')
	$LAST_ID_FILE = ini['apl_data_file']
	$FAV_URL = "https://api.twitter.com/1.1/favorites/list.json?count=200&screen_name=#{ini['screen_name']}";
	$SAVE_DIR = ini['save_dir']
	$ACCESS_TOKEN = OAuth::AccessToken.new(
		OAuth::Consumer.new(
			ini['oauth']['consumer_key'],
			ini['oauth']['consumer_key_secret'],
			{:site=>'https://api.twitter.com'}
		),
		ini['oauth']['access_token'],
		ini['oauth']['access_token_secret']
	)
	$USER_AGENT = 'save_fav_imgs'
end

$TWITTER_TRY_COUNT = 2
# API実行
def twitter_execute(uri, limit = 10)
	0.upto($TWITTER_TRY_COUNT) { |try_count|
		begin
			res = ""
			Timeout.timeout(60) {
				res = $ACCESS_TOKEN.get(uri, {'User-Agent' => "#{$USER_AGENT}"})
			}
			case res
			when Net::HTTPSuccess then
				if 0 < try_count then
					Log.info("success")
				end
				return res.body
			when Net::HTTPRedirection then
				if 0 < limit then
					req.path = res['location']
					Log.info("redirect to #{req.path}")
					return twitter_execute(req, limit - 1)
				else
					Log.warn("redirect over")
					return nil
				end
			when Net::HTTPNotFound, Net::HTTPForbidden, Net::HTTPBadGateway then
				Log.error("unretryable error. responce code #=> #{res.code} msg #=> #{res.message}")
				Log.debug(res.body)
				return nil
			else
				Log.warn("unknown responce code #=> #{res.code} msg #=> #{res.message}")
				Log.debug(res.body)
			end
		rescue => e
			if try_count < $TWITTER_TRY_COUNT
				Log.warn(e)
				Log.info('sleep 3 sec... and Retry to execute Twitter-Api !')
				sleep(3)
			else
				Log.error(e)
				Log.error("Retry over !!!")
			end
		end
	}
	return nil
end

def comp_str(a, b)
	return 0 if a == b
	return -1 if a == nil
	return 1 if b == nil
	return (a.size < b.size || a < b) ? -1 : 1
end

def save_images(json, since_id, max_id = nil)
	last_id = since_id
	first_id = max_id
	Log.warn("json #=> nil") if json == nil || json.empty?
	json_obj = JSON.parse(json)
	json_obj.map { |status|
		# 古いツイートをスキップする
		id = status['id_str'];
		break if comp_str(id, since_id) <= 0 && max_id.to_s.empty? == nil
		last_id = id if comp_str(last_id, id) < 0
		first_id = id if comp_str(id, first_id) < 0 || first_id.to_s.empty?
		# ツイートの情報を取得する
		Log.debug(id);
		entities = status['extended_entities']
		next if entities == nil
		media = entities['media']
		next if media == nil
		# ツイートの情報からディレクトリ名とファイルパスを作成する
		screen_name = status['user']['screen_name']
		created_at = Time::parse(status['created_at']).localtime.strftime('%Y%m%d_%H%M%S')
		text = status['text'].strip
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
			open("#{file_path}", 'wb') { |local_file|
				open(url) { |remote_file|
					local_file.write(remote_file.read)
				}
			}
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
opts.on('-r VALUE', '--roop VALUE', Integer, 'roop count') { |r|
	roop_count = r
}
sleep_sec = 1
opts.on('-s VALUE', '--sleep VALUE', Integer, 'sleep seconds') { |s|
	sleep_sec = s
}
opts.parse!(ARGV)
if roop_count == 1
	open("#{$LAST_ID_FILE}", 'r') { |f|
		last_id = f.read
	}
end
for i in 1..roop_count do
	sleep(sleep_sec) if i != 1
	url = $FAV_URL
	url << '&since_id='+ last_id.to_s if !last_id.to_s.empty? && roop_count == 1
	url << '&max_id='+ max_id.to_s if !max_id.to_s.empty? && roop_count != 1
	Log.info("execute-api #{url}");
	res = twitter_execute(url);
	last_id, max_id = save_images(res, last_id, max_id);
end
if roop_count == 1
	open("#{$LAST_ID_FILE}", 'w') { |f|
		f.write(last_id)
	}
end
Log.info("last_id #{last_id}")
Log.info('--終了--------------------')

